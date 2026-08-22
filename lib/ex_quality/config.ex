defmodule ExQuality.Config do
  @moduledoc """
  Loads and merges configuration from multiple sources.

  Configuration is resolved in the following order (later wins):
  1. Defaults
  2. Auto-detected tool availability
  3. Project config file (.quality.exs, read from the project root)
  4. The selected profile, if `--profile` named one
  5. CLI arguments

  ## Example .quality.exs

      [
        # Global options
        quick: false,

        # Override auto-detection: force disable dialyzer
        dialyzer: [enabled: false],

        # Credo options (enabled: :auto by default)
        credo: [
          strict: true,
          all: false
        ],

        # Doctor options
        doctor: [
          summary_only: true
        ],

        # Named bundles, selected with `mix quality --profile loop`
        profiles: [
          loop: [stages: [:format, :compile, :credo], test: [scope: :changed]],
          gate: []
        ]
      ]

  ## Configuration Options

  ### Global Options

  - `quick` - Quick mode: skip dialyzer and coverage enforcement (default: false)
  - `profiles` - Named option bundles, see "Profiles" below (default: `[]`)

  ### Stage Options

  Each stage supports:
  - `enabled` - :auto (use auto-detection) | true (force enable) | false (force disable)

  Stage-specific options:
  - `format.check` - Check formatting and fail on drift instead of rewriting
    files (default: false). See `ExQuality.Stages.Format`
  - `compile.warnings_as_errors` - Treat warnings as errors (default: true)
  - `compile.force` - Recompile from scratch (default: false)
  - `credo.strict` - Use strict mode (default: true)
  - `credo.all` - Check all files (default: false)
  - `credo.configs` - Names of the `.credo.exs` configs to run, in order
    (default: `nil`, meaning one run with no `--config-name`)
  - `dependencies.check_unused` - Check for unused dependencies (default: true)
  - `dependencies.audit` - Run security audit if available (default: :auto)
  - `doctor.summary_only` - Show only summary (default: false)
  - `gettext.source_locale` - The locale the source is written in, whose `.po`
    files are not checked (default: `"en"`)
  - `gettext.exclude` - Basenames to skip (default: `["errors.po"]`)
  - `gettext.extract` - Run `mix gettext.extract --merge` first, which writes to
    the repository and recompiles the project (default: false)
  - `sobelow.exit` - Confidence level that blocks, when `.sobelow-conf` sets no
    `exit:` of its own (default: "medium")
  - `sobelow.show_informational` - Render findings below that level as well as
    counting them (default: false)
  - `test.coverage` - :auto (measure when the project's config asks for it) |
    true (always measure) | false (never measure) (default: :auto)
  - `test.scope` - :all (the whole suite) | :changed (only the test files
    covering changed code) | a glob string (default: :all)
  - `test.base_ref` - What `scope: :changed` is measured against (default: the
    repository's default branch)

  ## Profiles

  A profile is a named bundle of the options above, so the fast path a project
  wants its agents to use has a name its docs can point at:

      profiles: [
        loop: [stages: [:format, :compile, :credo], test: [scope: :changed]],
        gate: []
      ]

  `mix quality --profile loop` merges the profile over the config file and under
  the CLI, so a switch still wins over the profile that a run selected.

  `stages:` is the allow-list of stage keys for the profile. Every other stage,
  built-in or custom, is reported as skipped naming the profile. A profile with
  no `stages:` key narrows nothing and only carries options, which is what an
  empty `gate: []` is for.

  An invocation with no `--profile` behaves exactly as it does without any
  profiles configured. An unknown profile name fails the run: falling back to
  "run everything" would turn a typo into a slow green, and falling back to the
  profile's intent would turn one into a fast green over nothing.
  """

  @defaults [
    # Global options
    quick: false,

    # Named option bundles, selected with --profile. Empty by default: this is
    # a 0.x library with real users, and the unprofiled path does not move.
    profiles: [],

    # Stage-specific options
    format: [
      # check: true makes the stage fail on drift instead of rewriting it.
      # Writing is the default because it is what the interactive loop wants,
      # and because it is what the stage has always done.
      check: false
    ],
    compile: [
      warnings_as_errors: true,
      force: false
    ],
    credo: [
      enabled: :auto,
      strict: true,
      all: false,
      # Names of the `.credo.exs` configs to run, in order. nil is one run with
      # no --config-name, which is credo's own default.
      configs: nil
    ],
    dialyzer: [
      enabled: :auto
    ],
    doctor: [
      enabled: :auto,
      summary_only: false
    ],
    gettext: [
      enabled: :auto,
      # The locale the source is written in. Its .po files are untranslated by
      # definition, so checking them would report every entry in them.
      source_locale: "en",
      exclude: ["errors.po"],
      # `mix gettext.extract --merge` writes to the repository and recompiles
      # the project, so it is opt-in rather than something a checker does.
      extract: false
    ],
    sobelow: [
      enabled: :auto,
      # Default threshold for a project whose .sobelow-conf sets no `exit:`.
      # A .sobelow-conf that does set one wins: it is the security decision.
      exit: "medium",
      show_informational: false
    ],
    dependencies: [
      enabled: :auto,
      check_unused: true,
      audit: :auto
    ],
    test: [
      # Coverage: uses excoveralls if available, otherwise `mix test --cover`
      # when the project sets a test_coverage threshold. Either way the
      # threshold comes from the tool's own config, not from here.
      # In quick mode: runs mix test only (no coverage enforcement)
      coverage: :auto,
      args: [],
      # How much of the suite to run. See `ExQuality.Scope`. :all is what an
      # unscoped run has always done, and narrowing is opt-in because a scope
      # that resolves to nothing is the one way this could report a false green.
      scope: :all,
      base_ref: nil
    ]
  ]

  @doc """
  Loads configuration with auto-detection and overrides.

  ## Resolution order (later wins):
  1. Defaults
  2. Auto-detected tool availability
  3. .quality.exs file
  4. The profile named by `--profile`, if any
  5. CLI arguments

  ## Examples

      # Load with CLI options
      config = ExQuality.Config.load(quick: true, skip_dialyzer: true)

      # Load with defaults only
      config = ExQuality.Config.load()
  """
  @spec load(keyword()) :: keyword()
  def load(cli_opts \\ []) do
    defaults = @defaults
    detected = resolve_auto_detection()
    file_config = load_file_config()
    cli_config = cli_to_config(cli_opts)

    config =
      defaults
      |> deep_merge(detected)
      |> deep_merge(file_config)
      |> apply_profile(Keyword.get(cli_opts, :profile))
      |> deep_merge(cli_config)

    # A custom stage that is malformed does not register, and a stage that does
    # not register is a check nobody is told is not running. That is a run to
    # fail rather than one to weaken quietly.
    ExQuality.Custom.validate!(config)

    config
  end

  @doc """
  Returns the name of the profile a loaded config was resolved with, or `nil`.

      iex> ExQuality.Config.profile(ExQuality.Config.load())
      nil
  """
  @spec profile(keyword()) :: atom() | nil
  def profile(config), do: Keyword.get(config, :profile)

  @doc """
  Merges the named profile into a config, or returns it unchanged for `nil`.

  Called by `load/1` between the config file and the CLI. `name` is a string
  because it comes from a switch, and the profile keys it is matched against are
  atoms because they come from a config file.

      iex> ExQuality.Config.apply_profile([credo: [strict: true]], nil)
      [credo: [strict: true]]

      iex> config = [profiles: [loop: [test: [scope: :changed]]]]
      iex> config |> ExQuality.Config.apply_profile("loop") |> Keyword.take([:profile, :test])
      [profile: :loop, test: [scope: :changed]]
  """
  @spec apply_profile(keyword(), String.t() | nil) :: keyword()
  def apply_profile(config, nil), do: config

  def apply_profile(config, name) do
    {key, profile} = fetch_profile!(config, name)

    config
    |> deep_merge(Keyword.delete(profile, :stages))
    |> deep_merge(profile_skips(config, profile, key))
    |> Keyword.put(:profile, key)
  end

  # Every stage key a profile's `stages:` list can allow. A custom stage's key is
  # added from the config, so a profile narrows a project's own checks the same
  # way it narrows the built-in ones.
  @profileable_keys [
    :format,
    :compile,
    :test,
    :credo,
    :dialyzer,
    :doctor,
    :gettext,
    :sobelow,
    :dependencies
  ]

  # An unknown name is an error, and the error lists what is known: the usual
  # cause is a profile that was never added to this project's .quality.exs.
  defp fetch_profile!(config, name) do
    profiles = profiles(config)

    case Enum.find(profiles, fn {key, _opts} -> to_string(key) == name end) do
      {key, opts} when is_list(opts) ->
        {key, opts}

      {key, opts} ->
        Mix.raise("Profile #{inspect(key)} must be a keyword list, got: #{inspect(opts)}")

      nil ->
        Mix.raise(
          "Unknown --profile #{inspect(name)}. " <>
            known_profiles(profiles) <> " Profiles are declared under profiles: in .quality.exs."
        )
    end
  end

  defp known_profiles([]), do: "No profiles are configured."

  defp known_profiles(profiles) do
    "Known profiles: " <>
      Enum.map_join(profiles, ", ", fn {key, _opts} -> inspect(key) end) <> "."
  end

  defp profiles(config) do
    case Keyword.get(config, :profiles, []) do
      profiles when is_list(profiles) ->
        if Keyword.keyword?(profiles) do
          profiles
        else
          Mix.raise("profiles: in .quality.exs must be a keyword list, got: #{inspect(profiles)}")
        end

      other ->
        Mix.raise("profiles: in .quality.exs must be a keyword list, got: #{inspect(other)}")
    end
  end

  # A stage left out of a profile's `stages:` is disabled the way a `--skip`
  # disables one, so it is announced as skipped naming the profile rather than
  # quietly missing from the run.
  defp profile_skips(config, profile, name) do
    case Keyword.fetch(profile, :stages) do
      :error ->
        []

      {:ok, allowed} when is_list(allowed) ->
        for key <- @profileable_keys ++ custom_keys(config), key not in allowed do
          {key, [enabled: false, disabled_by: {:cli, "not in profile #{inspect(name)}"}]}
        end

      {:ok, other} ->
        Mix.raise(
          "stages: in profile #{inspect(name)} must be a list of stage keys, got: #{inspect(other)}"
        )
    end
  end

  defp custom_keys(config) do
    config
    |> ExQuality.Custom.stages()
    |> Enum.flat_map(fn entry ->
      if Keyword.keyword?(entry), do: List.wrap(Keyword.get(entry, :key)), else: []
    end)
  end

  @doc """
  Determines if a stage should run based on config.

  - `enabled: :auto` → use detected availability
  - `enabled: true` → force enable (will error if tool missing)
  - `enabled: false` → force disable

  ## Examples

      config = ExQuality.Config.load()
      ExQuality.Config.stage_enabled?(config, :credo)
      #=> true (if credo is installed)

      config = ExQuality.Config.load(skip_credo: true)
      ExQuality.Config.stage_enabled?(config, :credo)
      #=> false
  """
  @spec stage_enabled?(keyword(), atom()) :: boolean()
  def stage_enabled?(config, stage) do
    stage_config = Keyword.get(config, stage, [])
    enabled = Keyword.get(stage_config, :enabled, :auto)
    available = Keyword.get(stage_config, :available, true)

    case enabled do
      :auto -> available
      true -> true
      false -> false
    end
  end

  @doc """
  Returns why a stage will not run, or `nil` when it will.

  The reason is meant to be shown to the reader, because a stage that is
  silently omitted reads as a stage that passed.

  ## Examples

      config = ExQuality.Config.load(skip_credo: true)
      ExQuality.Config.skip_reason(config, :credo)
      #=> "--skip-credo"

      config = ExQuality.Config.load()
      ExQuality.Config.skip_reason(config, :doctor)
      #=> ":doctor not installed"
  """
  @spec skip_reason(keyword(), atom()) :: String.t() | nil
  def skip_reason(config, stage) do
    case skip(config, stage) do
      nil -> nil
      {reason, _kind} -> reason
    end
  end

  @doc """
  Returns why a stage will not run and what kind of skip that is, or `nil`
  when it will run.

  The kind is `:run` when the skip came from the command line - a switch or a
  profile selected for this invocation - because a full `mix quality` closes
  it. It is `:project` when the skip came from `.quality.exs` or from the tool
  not being installed, because a fuller run cannot close that. See
  `t:ExQuality.Stage.skip_kind/0`.

  ## Examples

      config = ExQuality.Config.load(skip_credo: true)
      ExQuality.Config.skip(config, :credo)
      #=> {"--skip-credo", :run}

      config = ExQuality.Config.load()
      ExQuality.Config.skip(config, :doctor)
      #=> {":doctor not installed", :project}
  """
  @spec skip(keyword(), atom()) :: {String.t(), ExQuality.Stage.skip_kind()} | nil
  def skip(config, stage) do
    if stage_enabled?(config, stage) do
      nil
    else
      stage_config = Keyword.get(config, stage, [])

      case Keyword.get(stage_config, :disabled_by) do
        # The generic switch carries its own spelling, because `--skip nullability`
        # names a stage that has no `--skip-nullability` to point at.
        {:cli, switch} -> {switch, :run}
        :cli -> {"--skip-#{stage}", :run}
        :config -> {"disabled in .quality.exs", :project}
        _other -> {unavailable_reason(stage), :project}
      end
    end
  end

  defp unavailable_reason(stage) do
    case ExQuality.Tools.package(stage) do
      nil -> "disabled"
      package -> "#{inspect(package)} not installed"
    end
  end

  defp resolve_auto_detection do
    tools = ExQuality.Tools.detect()

    [
      credo: [available: tools.credo],
      dialyzer: [available: tools.dialyzer],
      doctor: [available: tools.doctor],
      gettext: [available: tools.gettext],
      sobelow: [available: tools.sobelow],
      dependencies: [audit_available: tools.audit],
      test: [coverage_available: tools.coverage]
    ]
  end

  @config_file ".quality.exs"

  @doc """
  Returns the path of the `.quality.exs` that applies here, or `nil`.

  The file belongs to the project, not to wherever the shell happened to be
  when `mix quality` was run. An umbrella child with no file of its own falls
  back to the umbrella root's, because the settings describe the tree.

  Finding the umbrella root needs `Mix.Project.parent_umbrella_project_file/0`,
  which arrived in Elixir 1.15. On 1.14 only the current project's root is
  looked at.
  """
  @spec config_path() :: String.t() | nil
  def config_path, do: config_path(project_root(), umbrella_root())

  @doc """
  Returns the `.quality.exs` under `project_root`, or under `umbrella_root`
  when the project has none of its own, or `nil` when neither has one.

  Either root may be `nil`, meaning there is no such directory to look in.
  """
  @spec config_path(String.t() | nil, String.t() | nil) :: String.t() | nil
  def config_path(project_root, umbrella_root) do
    [project_root, umbrella_root]
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.map(&Path.join(&1, @config_file))
    |> Enum.find(&File.exists?/1)
  end

  defp project_root do
    case Mix.Project.get() && Mix.Project.project_file() do
      nil -> File.cwd!()
      file -> Path.dirname(file)
    end
  end

  # `parent_umbrella_project_file/0` is Elixir 1.15+, and this project supports
  # 1.14, so its absence means "no umbrella root known" rather than an error.
  defp umbrella_root do
    # Called through a variable rather than as `Mix.Project.…`, because a
    # direct call to a function that does not exist on 1.14 does not compile
    # cleanly there.
    mix_project = Mix.Project

    if function_exported?(mix_project, :parent_umbrella_project_file, 0) do
      case mix_project.parent_umbrella_project_file() do
        nil -> nil
        file -> Path.dirname(file)
      end
    end
  end

  defp load_file_config do
    case config_path() do
      nil ->
        []

      path ->
        case Code.eval_file(path) do
          {config, _} when is_list(config) ->
            annotate_disabled(config, :config)

          _ ->
            []
        end
    end
  end

  # Records where a `enabled: false` came from, so a skipped stage can name the
  # switch or the file that turned it off rather than just saying "disabled".
  defp annotate_disabled(config, source) do
    Enum.map(config, fn
      {stage, opts} when is_list(opts) ->
        if Keyword.get(opts, :enabled) == false and not Keyword.has_key?(opts, :disabled_by) do
          {stage, Keyword.put(opts, :disabled_by, source)}
        else
          {stage, opts}
        end

      pair ->
        pair
    end)
  end

  # Every stage has a --skip-<stage> switch, and they all mean the same thing,
  # so they are one table rather than one branch each.
  @skip_switches [:credo, :dialyzer, :doctor, :gettext, :sobelow, :dependencies]

  defp cli_to_config(opts) do
    config =
      Enum.reduce(@skip_switches, [], fn stage, config ->
        if opts[:"skip_#{stage}"] do
          Keyword.put(config, stage, enabled: false)
        else
          config
        end
      end)

    config
    |> put_skips(opts)
    # --quick mode: skip dialyzer, skip coverage enforcement
    |> put_flag(opts, :quick)
    |> put_flag(opts, :verbose)
    |> put_flag(opts, :until_first_failure)
    |> put_test_args(opts)
    |> put_test_scope(opts)
    |> annotate_disabled(:cli)
  end

  # `--skip <key>` is repeatable and works for a custom stage as well as a
  # built-in one, because `@switches` is static and a custom key cannot have a
  # `--skip-<key>` generated for it.
  defp put_skips(config, opts) do
    opts
    |> Keyword.get_values(:skip)
    |> Enum.reduce(config, fn name, config ->
      Keyword.put(config, String.to_atom(name),
        enabled: false,
        disabled_by: {:cli, "--skip #{name}"}
      )
    end)
  end

  defp put_flag(config, opts, key) do
    if opts[key], do: Keyword.put(config, key, true), else: config
  end

  defp put_test_args(config, opts) do
    if opts[:test_args], do: put_test_option(config, :args, opts[:test_args]), else: config
  end

  # `--test-scope` is parsed here rather than at the switch, so a bad value fails
  # the run with the same message a bad `.quality.exs` value gets.
  defp put_test_scope(config, opts) do
    case Keyword.fetch(opts, :test_scope) do
      :error ->
        config

      {:ok, value} ->
        case ExQuality.Scope.parse(value) do
          {:ok, scope} -> put_test_option(config, :scope, scope)
          {:error, message} -> Mix.raise("Invalid --test-scope: #{message}")
        end
    end
  end

  # `test:` can be set by more than one switch, so each one merges into whatever
  # the last put there rather than replacing it.
  defp put_test_option(config, key, value) do
    Keyword.update(config, :test, [{key, value}], &Keyword.put(&1, key, value))
  end

  defp deep_merge(left, right) do
    Keyword.merge(left, right, fn _key, left_val, right_val ->
      if Keyword.keyword?(left_val) and Keyword.keyword?(right_val) do
        Keyword.merge(left_val, right_val)
      else
        right_val
      end
    end)
  end
end
