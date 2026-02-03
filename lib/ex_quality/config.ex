defmodule ExQuality.Config do
  @moduledoc """
  Loads and merges configuration from multiple sources.

  Configuration is resolved in the following order (later wins):
  1. Defaults
  2. Auto-detected tool availability
  3. Project config file (.quality.exs)
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
  - `credo.strict` - Use strict mode (default: true)
  - `credo.all` - Check all files (default: false)
  - `dependencies.check_unused` - Check for unused dependencies (default: true)
  - `dependencies.audit` - Run security audit if available (default: :auto)
  - `doctor.summary_only` - Show only summary (default: false)
  """

  @defaults [
    # Global options
    quick: false,

    # Stage-specific options
    compile: [
      warnings_as_errors: true
    ],
    credo: [
      enabled: :auto,
      strict: true,
      all: false
    ],
    dialyzer: [
      enabled: :auto
    ],
    doctor: [
      enabled: :auto,
      summary_only: false
    ],
    gettext: [
      enabled: :auto
    ],
    dependencies: [
      enabled: :auto,
      check_unused: true,
      audit: :auto
    ],
    test: [
      # Coverage: uses excoveralls if available, threshold from coveralls config
      # In quick mode: runs mix test only (no coverage enforcement)
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

    defaults
    |> deep_merge(detected)
    |> deep_merge(file_config)
    |> deep_merge(cli_config)
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

  defp resolve_auto_detection do
    tools = ExQuality.Tools.detect()

    [
      credo: [available: tools.credo],
      dialyzer: [available: tools.dialyzer],
      doctor: [available: tools.doctor],
      gettext: [available: tools.gettext],
      dependencies: [audit_available: tools.audit],
      test: [coverage_available: tools.coverage]
    ]
  end

  defp load_file_config do
    path = Path.join(File.cwd!(), ".quality.exs")

    if File.exists?(path) do
      case Code.eval_file(path) do
        {config, _} when is_list(config) ->
          config

        _ ->
          []
      end
    else
      []
    end
  end

  defp cli_to_config(opts) do
    config = []

    # --quick mode: skip dialyzer, skip coverage enforcement
    config =
      if opts[:quick] do
        Keyword.put(config, :quick, true)
      else
        config
      end

    # Individual skip flags
    config =
      if opts[:skip_dialyzer] do
        Keyword.put(config, :dialyzer, enabled: false)
      else
        config
      end

    config =
      if opts[:skip_credo] do
        Keyword.put(config, :credo, enabled: false)
      else
        config
      end

    config =
      if opts[:skip_doctor] do
        Keyword.put(config, :doctor, enabled: false)
      else
        config
      end

    config =
      if opts[:skip_gettext] do
        Keyword.put(config, :gettext, enabled: false)
      else
        config
      end

    config =
      if opts[:skip_dependencies] do
        Keyword.put(config, :dependencies, enabled: false)
      else
        config
      end

    config =
      if opts[:verbose] do
        Keyword.put(config, :verbose, true)
      else
        config
      end

    config =
      if opts[:test_args] do
        Keyword.put(config, :test, args: opts[:test_args])
      else
        config
      end

    config
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
