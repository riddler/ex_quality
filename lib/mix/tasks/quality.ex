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
  - `--skip-sobelow` - Skip Sobelow security analysis
  - `--skip-dependencies` - Skip dependency checks (unused deps and security audit)
  - `--verbose` - Show full output even on success
  - `--format json` - Write a JSON report to stdout, human output to stderr
  - `--report PATH` - Write a JSON report to PATH, human output to stdout

  ## Passing Test Options

  You can pass extra arguments to `mix test` or `mix coveralls` using `--`:

      mix quality -- --only integration
      mix quality --quick -- --include slow --seed 0

  Arguments after `--` are passed directly to the test command.

  Alternatively, configure test args in `.quality.exs`:

      test: [
        args: ["--only", "integration"]
      ]

  CLI args (after `--`) override config file args (no merge).

  ## Auto-Detection

  Stages are automatically enabled based on installed dependencies:

  - `:credo` → enables Credo stage
  - `:dialyxir` → enables Dialyzer stage
  - `:doctor` → enables Doctor stage
  - `:gettext` → enables Gettext translation checks
  - `:sobelow` → enables Sobelow security analysis
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
  or override auto-detection. See `Config` for options.

  ## Example Output

      Running quality checks...

      ✓ Format: No changes needed (0.1s)
      ✓ Compile: dev + test compiled (warnings as errors) (1.8s)

      Running analysis stages in parallel...

      ○ Doctor: skipped (:doctor not installed)
      ✓ Credo: No issues (1.2s)
      ✓ Tests: 248 passed, 0 failed, 87.3% coverage (5.2s)
      ✓ Dialyzer: No warnings (32.1s)

      ✓ All quality checks passed!

  ## Skipped Stages

  A stage that is disabled, or whose tool is not installed, prints a line
  saying so with the reason. A run never leaves out a stage silently: a
  missing stage would otherwise read as a stage that passed.

  ## Machine-Readable Output

  The exit code says the run failed, not what failed. A caller that wants to
  route on the result asks for a report instead of scraping the console:

      mix quality --format json           # report on stdout, human on stderr
      mix quality --report .quality.json  # human on stdout, report to a file

  `--report` is usually the more useful of the two, because it leaves the
  human stream intact. Both can be given at once. See `ExQuality.Report` for
  the shape.

  ## Dialyzer PLT

  A run that has to build the Dialyzer PLT says so while it happens
  (`⋯ Dialyzer: building PLT (this is a one-time cost)`) and reports it in the
  stage summary, because a multi-minute wait behind a single line of output
  otherwise reads as a hang. `mix quality.plt` builds it outside a run, which
  is what a container image or a CI job should cache.
  """

  use Mix.Task

  alias ExQuality.Config
  alias ExQuality.Finding
  alias ExQuality.Printer
  alias ExQuality.Report
  alias ExQuality.Stage
  alias ExQuality.Stages.Compile
  alias ExQuality.Stages.Credo
  alias ExQuality.Stages.Dependencies
  alias ExQuality.Stages.Dialyzer
  alias ExQuality.Stages.Doctor
  alias ExQuality.Stages.Format
  alias ExQuality.Stages.Gettext
  alias ExQuality.Stages.Sobelow
  alias ExQuality.Stages.Test

  # Optional analysis stages, in the order they are considered. Tests are not
  # here because they always run.
  @analysis_stages [
    {:credo, Credo, "Credo"},
    {:dialyzer, Dialyzer, "Dialyzer"},
    {:doctor, Doctor, "Doctor"},
    {:gettext, Gettext, "Gettext"},
    {:sobelow, Sobelow, "Sobelow"},
    {:dependencies, Dependencies, "Dependencies"}
  ]

  @switches [
    quick: :boolean,
    skip_dialyzer: :boolean,
    skip_credo: :boolean,
    skip_doctor: :boolean,
    skip_gettext: :boolean,
    skip_sobelow: :boolean,
    skip_dependencies: :boolean,
    verbose: :boolean,
    format: :string,
    report: :string
  ]

  @doc """
  Runs the quality check task.
  """
  def run(args) do
    {opts, remaining} = OptionParser.parse!(args, switches: @switches)
    opts = if remaining != [], do: Keyword.put(opts, :test_args, remaining), else: opts
    config = Config.load(opts)
    reporting = reporting(opts)

    # The report owns stdout in JSON mode, so the human stream moves aside for
    # the run and the previous shell is put back whatever happens.
    shell = Mix.shell()
    if reporting.format == :json, do: Mix.shell(ExQuality.Shell.Stderr)

    try do
      run_checks(config, reporting)
    after
      Mix.shell(shell)
    end
  end

  defp reporting(opts) do
    format =
      case Keyword.get(opts, :format, "human") do
        "human" -> :human
        "json" -> :json
        other -> Mix.raise(~s(Unknown --format #{inspect(other)}. Expected "human" or "json".))
      end

    %{
      format: format,
      path: Keyword.get(opts, :report),
      # Failure details are written verbatim rather than through the shell, so
      # they need to be told where the human stream went.
      device: if(format == :json, do: :stderr, else: :stdio)
    }
  end

  defp run_checks(config, reporting) do
    started = System.monotonic_time(:millisecond)

    Mix.shell().info("Running quality checks...\n")

    # Phase 1: Auto-fix (format)
    format_result = Format.run(config)
    display_phase_result(format_result)

    # Phase 2: Compile (blocking gate)
    compile_result = Compile.run(config)
    display_phase_result(compile_result)

    if compile_result.status == :error do
      # Nothing downstream ran, and a stage that says nothing reads as a stage
      # that passed, so every one of them is reported as skipped.
      not_run = analysis_stages_not_run(config, "compile failed")
      Enum.each(not_run, &display_phase_result/1)

      finish([format_result, compile_result | not_run], started, reporting, "Compilation failed")
    else
      # Phase 3: Analysis (parallel with streaming)
      Mix.shell().info("\nRunning analysis stages in parallel...\n")

      analysis_results = run_analysis_stages(config)
      all_results = [format_result, compile_result | analysis_results]

      finish(all_results, started, reporting, nil)
    end
  end

  # One exit for every run: render the human verdict, emit the report, then
  # fail. The report is written before raising so a caller still gets it.
  defp finish(results, started, reporting, message) do
    failures = Enum.filter(results, &(&1.status == :error))

    if failures != [] do
      Mix.shell().info("")
      display_failure_details(failures, reporting.device)
    else
      Mix.shell().info("\n✓ All quality checks passed!")
    end

    emit_report(results, System.monotonic_time(:millisecond) - started, reporting)

    if failures != [] do
      Mix.raise(message || "#{length(failures)} quality check(s) failed")
    end
  end

  defp emit_report(_results, _duration_ms, %{format: :human, path: nil}), do: :ok

  defp emit_report(results, duration_ms, reporting) do
    json = results |> Report.build(duration_ms) |> Report.encode!()

    if reporting.path, do: File.write!(reporting.path, json)
    if reporting.format == :json, do: IO.write(json)

    :ok
  end

  defp run_analysis_stages(config) do
    {:ok, _pid} = Printer.start_link()

    try do
      {stages, skipped} = build_analysis_stages(config)

      # Announce the stages that will not run before the ones that will, so the
      # reader knows what this run is not evidence for.
      Enum.each(skipped, &Printer.print_result/1)

      {writers, readers} =
        Enum.split_with(stages, fn {_stage, module, _name} ->
          Stage.kind(module, config) == :writer
        end)

      # Writers go first, one at a time. A stage that recompiles the project
      # rewrites the beams the readers are part-way through, and the reader
      # that notices reports a failure about the build rather than the code.
      writer_results = Enum.map(writers, &run_stage(&1, config))

      tasks = Enum.map(readers, fn stage -> Task.async(fn -> run_stage(stage, config) end) end)

      skipped ++ writer_results ++ Enum.map(tasks, &Task.await(&1, :infinity))
    after
      Printer.stop()
    end
  end

  defp run_stage({_stage, module, _name}, config) do
    result = module.run(config)
    Printer.print_result(result)
    result
  end

  # Every optional stage is either run or reported as skipped with its reason.
  # Tests always run (but coverage enforcement is skipped in quick mode).
  defp build_analysis_stages(config) do
    {stages, skipped} =
      Enum.reduce(@analysis_stages, {[], []}, fn {stage, module, name}, {stages, skipped} ->
        case stage_skip_reason(config, stage) do
          nil -> {[{stage, module, name} | stages], skipped}
          reason -> {stages, [Stage.skipped(name, reason) | skipped]}
        end
      end)

    {Enum.reverse([{:test, Test, "Tests"} | stages]), Enum.reverse(skipped)}
  end

  # The stages of a run that stopped before the analysis phase: the ones that
  # would have run take the given reason, the rest keep their own.
  defp analysis_stages_not_run(config, reason) do
    {stages, skipped} = build_analysis_stages(config)

    skipped ++ Enum.map(stages, fn {_stage, _module, name} -> Stage.skipped(name, reason) end)
  end

  defp stage_skip_reason(config, :dialyzer) do
    case Config.skip_reason(config, :dialyzer) do
      nil -> if Keyword.get(config, :quick, false), do: "--quick"
      reason -> reason
    end
  end

  defp stage_skip_reason(config, stage), do: Config.skip_reason(config, stage)

  # Compile never skips, so this renders one status it can never be given from
  # the compile phase; the branch is kept so every status has one renderer.
  @dialyzer {:nowarn_function, [display_phase_result: 1, skip_reason: 1]}
  @spec display_phase_result(ExQuality.Stage.result()) :: :ok
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
        Mix.shell().info("○ #{result.name}: skipped#{skip_reason(result)}")
    end
  end

  defp skip_reason(%{summary: reason}) when is_binary(reason) and reason != "", do: " (#{reason})"
  defp skip_reason(_result), do: ""

  defp display_failure_details(failures, device) do
    Enum.each(failures, fn failure ->
      Mix.shell().info(String.duplicate("─", 60))
      Mix.shell().error("#{failure.name} - FAILED")
      Mix.shell().info(String.duplicate("─", 60))

      display_failure_body(failure, device)

      Mix.shell().info("")
    end)
  end

  # A stage that parsed its tool's output shows findings; one that did not
  # shows the tool's output in full. Nothing is truncated either way.
  defp display_failure_body(failure, device) do
    case Stage.findings(failure) do
      [] -> if failure.output != "", do: IO.write(device, failure.output)
      findings -> IO.write(device, Finding.render(findings))
    end
  end

  defp format_duration(ms) when ms < 1000, do: "#{ms}ms"
  defp format_duration(ms), do: "#{Float.round(ms / 1000, 1)}s"
end
