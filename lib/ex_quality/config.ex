defmodule ExQuality.Config do
  @moduledoc """
  Loads and merges configuration from multiple sources.

  Configuration is resolved in the following order (later wins):
  1. Defaults
  2. Auto-detected tool availability
  3. Project config file (.quality.exs, read from the project root)
  4. CLI arguments

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
        ]
      ]

  ## Configuration Options

  ### Global Options

  - `quick` - Quick mode: skip dialyzer and coverage enforcement (default: false)

  ### Stage Options

  Each stage supports:
  - `enabled` - :auto (use auto-detection) | true (force enable) | false (force disable)

  Stage-specific options:
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
  """

  @defaults [
    # Global options
    quick: false,

    # Stage-specific options
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
      args: []
    ]
  ]

  @doc """
  Loads configuration with auto-detection and overrides.

  ## Resolution order (later wins):
  1. Defaults
  2. Auto-detected tool availability
  3. .quality.exs file
  4. CLI arguments

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
      |> deep_merge(cli_config)

    # A custom stage that is malformed does not register, and a stage that does
    # not register is a check nobody is told is not running. That is a run to
    # fail rather than one to weaken quietly.
    ExQuality.Custom.validate!(config)

    config
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
    if stage_enabled?(config, stage) do
      nil
    else
      stage_config = Keyword.get(config, stage, [])

      case Keyword.get(stage_config, :disabled_by) do
        # The generic switch carries its own spelling, because `--skip nullability`
        # names a stage that has no `--skip-nullability` to point at.
        {:cli, switch} -> switch
        :cli -> "--skip-#{stage}"
        :config -> "disabled in .quality.exs"
        _other -> unavailable_reason(stage)
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
    |> put_test_args(opts)
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
    if opts[:test_args], do: Keyword.put(config, :test, args: opts[:test_args]), else: config
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
