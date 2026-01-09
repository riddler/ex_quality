defmodule Mix.Tasks.Quality do
  @shortdoc "Runs parallel code quality checks with auto-fix"

  @moduledoc """
  Runs code quality checks in parallel with actionable feedback.

  Automatically fixes formatting issues, then runs all analysis stages
  in parallel with streaming output.

  ## Execution Phases

  1. **Auto-fix** - Runs `mix format` to fix formatting
  2. **Compile** - Compiles dev + test environments in parallel
  3. **Analysis** - Runs enabled checks in parallel (credo, dialyzer, doctor, tests)

  ## Usage

      mix quality

  ## Options

  - `--quick` - Quick mode for development: skips dialyzer and coverage enforcement
  - `--skip-dialyzer` - Skip Dialyzer type checking
  - `--skip-credo` - Skip Credo static analysis
  - `--skip-doctor` - Skip Doctor documentation checks
  - `--skip-gettext` - Skip Gettext translation checks
  - `--skip-dependencies` - Skip dependency checks (unused deps and security audit)
  - `--verbose` - Show full output even on success

  ## Auto-Detection

  Stages are automatically enabled based on installed dependencies:

  - `:credo` → enables Credo stage
  - `:dialyxir` → enables Dialyzer stage
  - `:doctor` → enables Doctor stage
  - `:gettext` → enables Gettext translation checks
  - `:mix_audit` → enables security audit in Dependencies stage
  - `:excoveralls` → uses `mix coveralls` instead of `mix test`

  ## Quick Mode

  Use `--quick` during active development when you haven't finished all
  implementation tasks (like writing tests). Quick mode:

  - Skips Dialyzer (slow)
  - Runs `mix test` instead of `mix coveralls` (tests must pass, but
    coverage threshold is not enforced)

  This lets you iterate quickly while still catching obvious issues.

  ## Configuration

  Create `.quality.exs` in your project root to customize behavior
  or override auto-detection. See `Quality.Config` for options.

  ## Example Output

      Running quality checks...

      ✓ Format: No changes needed (0.1s)
      ✓ Compile: dev + test compiled (warnings as errors) (1.8s)

      Running analysis stages in parallel...

      ✓ Credo: No issues (1.2s)
      ✓ Tests: 248 passed, 0 failed, 87.3% coverage (5.2s)
      ✓ Dialyzer: No warnings (32.1s)

      ✅ All quality checks passed!
  """

  use Mix.Task

  @switches [
    quick: :boolean,
    skip_dialyzer: :boolean,
    skip_credo: :boolean,
    skip_doctor: :boolean,
    skip_gettext: :boolean,
    skip_dependencies: :boolean,
    verbose: :boolean
  ]

  @doc """
  Runs the quality check task.
  """
  def run(args) do
    {opts, _remaining} = OptionParser.parse!(args, switches: @switches)
    config = Quality.Config.load(opts)

    Mix.shell().info("Running quality checks...\n")

    # Phase 1: Auto-fix (format)
    format_result = Quality.Stages.Format.run(config)
    display_phase_result(format_result)

    # Phase 2: Compile (blocking gate)
    compile_result = Quality.Stages.Compile.run(config)
    display_phase_result(compile_result)

    if compile_result.status == :error do
      Mix.shell().info("")
      display_failure_details([compile_result])
      Mix.raise("Compilation failed")
    end

    # Phase 3: Analysis (parallel with streaming)
    Mix.shell().info("\nRunning analysis stages in parallel...\n")

    analysis_results = run_analysis_stages(config)

    # Show results and check for failures
    all_results = [format_result, compile_result | analysis_results]
    failures = Enum.filter(all_results, &(&1.status == :error))

    if failures != [] do
      Mix.shell().info("")
      display_failure_details(failures)
      Mix.raise("#{length(failures)} quality check(s) failed")
    else
      Mix.shell().info("\n✅ All quality checks passed!")
    end
  end

  defp run_analysis_stages(config) do
    Quality.Printer.start_link()

    try do
      stages = build_analysis_stages(config)

      tasks =
        Enum.map(stages, fn {_name, module} ->
          Task.async(fn ->
            result = module.run(config)
            Quality.Printer.print_result(result)
            result
          end)
        end)

      Enum.map(tasks, &Task.await(&1, :infinity))
    after
      Quality.Printer.stop()
    end
  end

  defp build_analysis_stages(config) do
    quick_mode = Keyword.get(config, :quick, false)
    stages = []

    # Add Credo if enabled
    stages =
      if Quality.Config.stage_enabled?(config, :credo) do
        [{:credo, Quality.Stages.Credo} | stages]
      else
        stages
      end

    # Add Dialyzer if enabled and not in quick mode
    stages =
      if Quality.Config.stage_enabled?(config, :dialyzer) and not quick_mode do
        [{:dialyzer, Quality.Stages.Dialyzer} | stages]
      else
        stages
      end

    # Add Doctor if enabled
    stages =
      if Quality.Config.stage_enabled?(config, :doctor) do
        [{:doctor, Quality.Stages.Doctor} | stages]
      else
        stages
      end

    # Add Gettext if enabled
    stages =
      if Quality.Config.stage_enabled?(config, :gettext) do
        [{:gettext, Quality.Stages.Gettext} | stages]
      else
        stages
      end

    # Add Dependencies if enabled
    stages =
      if Quality.Config.stage_enabled?(config, :dependencies) do
        [{:dependencies, Quality.Stages.Dependencies} | stages]
      else
        stages
      end

    # Tests always run (but coverage enforcement skipped in quick mode)
    [{:test, Quality.Stages.Test} | stages]
  end

  defp display_phase_result(result) do
    case result.status do
      :ok ->
        Mix.shell().info(
          "✓ #{result.name}: #{result.summary} (#{format_duration(result.duration_ms)})"
        )

      :error ->
        Mix.shell().error(
          "✗ #{result.name}: #{result.summary} (#{format_duration(result.duration_ms)})"
        )

      :skipped ->
        Mix.shell().info("○ #{result.name}: Skipped (#{format_duration(result.duration_ms)})")
    end
  end

  defp display_failure_details(failures) do
    Enum.each(failures, fn failure ->
      Mix.shell().info(String.duplicate("─", 60))
      Mix.shell().error("#{failure.name} - FAILED")
      Mix.shell().info(String.duplicate("─", 60))

      if failure.output != "" do
        Mix.shell().info(failure.output)
      end

      Mix.shell().info("")
    end)
  end

  defp format_duration(ms) when ms < 1000, do: "#{ms}ms"
  defp format_duration(ms), do: "#{Float.round(ms / 1000, 1)}s"
end
