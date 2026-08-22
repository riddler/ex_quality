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

  `--until-first-failure` replaces all three with one sequential pass, cheapest
  stage first, stopping at the first failure. See "An inner loop" below.

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
  - `--skip KEY` - Skip any stage by key, built-in or custom; repeatable
  - `--profile NAME` - Run a named bundle of options from `.quality.exs`
  - `--test-scope all|changed|GLOB` - How much of the suite to run
  - `--until-first-failure` - Stop at the first failing stage, cheapest first
  - `--verbose` - Show full output even on success
  - `--format json` - Write a JSON report to stdout, human output to stderr
  - `--report PATH` - Write a JSON report to PATH, human output to stdout
    (`--report -` writes it to stdout, as `--format json` does)

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

  ## An inner loop, as opposed to a gate

  A full run is a good thing to require before a push and a bad thing to run
  between edits, and every switch above narrows *which checks run* when the
  expensive question is *how much code they run over*. On a large suite the tests
  are most of the wall clock, and `--quick` does not touch them: it removes
  dialyzer and the coverage threshold and still runs every test.

      mix quality --test-scope changed        # only the tests covering your edits
      mix quality --profile loop             # a named bundle, see below
      mix quality --until-first-failure      # stop at the first thing to fix

  `--test-scope changed` maps the files you have changed, committed or not, to
  the test files covering them. A scope that resolves to no test files runs the
  whole suite instead, because a green run of nothing is the one result that
  would be worse than a slow one. Coverage is reported as skipped on a scoped
  run, never as a number over a subset. See `ExQuality.Scope`.

  A profile gives that fast path a name, so a project's docs and its agent
  instructions can point at one word instead of a switch list:

      profiles: [
        loop: [stages: [:format, :compile, :credo], test: [scope: :changed]],
        gate: []
      ]

  A run with no `--profile` behaves exactly as it did before profiles existed.
  See `ExQuality.Config` for how a profile merges, and what an unknown name does.

  ## Configuration

  Create `.quality.exs` in your project root to customize behavior
  or override auto-detection. See `Config` for options.

  ## Custom Stages

  A project's own check - a house rule, a schema linter, a shell script gate -
  runs as a stage of the run rather than beside it, declared under `custom:` in
  `.quality.exs`. It gets the same parallelism, timing, printer and JSON report
  as a built-in stage, which is what lets a caller route its findings. See
  `ExQuality.Custom`.

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
      mix quality --report -              # the same as --format json

  `--report PATH` is usually the most useful, because it leaves the human
  stream intact, and it can be given alongside `--format json`.

  The root of the report carries `profile`, `scope` and `base_ref`, because
  `status` alone does not say what a run is evidence for: a green run over three
  test files and a green full run are different claims. See `ExQuality.Report`
  for the shape.

  ## Dialyzer PLT

  A run that has to build the Dialyzer PLT says so while it happens
  (`⋯ Dialyzer: building PLT (this is a one-time cost)`) and reports it in the
  stage summary, because a multi-minute wait behind a single line of output
  otherwise reads as a hang. `mix quality.plt` builds it outside a run, which
  is what a container image or a CI job should cache.
  """

  use Mix.Task

  alias ExQuality.Config
  alias ExQuality.Custom
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
    skip: :keep,
    profile: :string,
    test_scope: :string,
    until_first_failure: :boolean,
    verbose: :boolean,
    format: :string,
    report: :string
  ]

  # Cheapest first, for --until-first-failure. An iterating caller does not need
  # a full battery report, it needs the next thing to fix, and paying a minute of
  # tests to be told about a formatting error is the opposite of that. The order
  # is stated rather than derived because the analysis phase runs in parallel and
  # so has never needed one. A custom stage's cost is unknown, so it is placed
  # with the linters: they are what a project's own checks usually are, and being
  # wrong there costs a few seconds rather than a suite.
  @cost_order [
    :format,
    :compile,
    :dependencies,
    :sobelow,
    :gettext,
    :credo,
    :doctor,
    :custom,
    :dialyzer,
    :test
  ]

  @doc """
  Runs the quality check task.
  """
  def run(args) do
    case execute(args) do
      %{failure: nil} -> :ok
      %{failure: message} -> Mix.raise(message)
    end
  end

  @doc false
  # Runs the gate exactly as `mix quality` does - same printing, same report
  # emission - and returns `%{report: report, config: config, failure: message}`
  # instead of exiting, `failure` being `nil` on a green run. This is the
  # in-process entry point `mix quality.verify` attests over, so the run it
  # verifies is the run that printed, not a second one.
  @spec execute([String.t()]) :: %{
          report: ExQuality.Report.t(),
          config: keyword(),
          failure: String.t() | nil
        }
  def execute(args) do
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
    requested =
      case Keyword.get(opts, :format, "human") do
        "human" -> :human
        "json" -> :json
        other -> Mix.raise(~s(Unknown --format #{inspect(other)}. Expected "human" or "json".))
      end

    path = Keyword.get(opts, :report)

    # `--report -` is the shell's spelling of "to stdout", and a caller that
    # wants the report there wants nothing else there: the human stream moves to
    # stderr rather than being interleaved into JSON nobody can parse.
    format = if path == "-", do: :json, else: requested

    %{
      format: format,
      path: if(path == "-", do: nil, else: path),
      # Failure details are written verbatim rather than through the shell, so
      # they need to be told where the human stream went.
      device: if(format == :json, do: :stderr, else: :stdio)
    }
  end

  defp run_checks(config, reporting) do
    started = System.monotonic_time(:millisecond)

    Mix.shell().info("Running quality checks...\n")

    if Keyword.get(config, :until_first_failure, false) do
      run_serially(config, started, reporting)
    else
      run_in_phases(config, started, reporting)
    end
  end

  defp run_in_phases(config, started, reporting) do
    # Phase 1: Auto-fix (format)
    format_result = run_or_skip(config, :format, "Format", &Format.run/1)
    Printer.print_result(format_result)

    # Phase 2: Compile (blocking gate)
    compile_result = run_or_skip(config, :compile, "Compile", &Compile.run/1)
    Printer.print_result(compile_result)

    if compile_result.status == :error do
      # Nothing downstream ran, and a stage that says nothing reads as a stage
      # that passed, so every one of them is reported as skipped.
      not_run = analysis_stages_not_run(config, "compile failed")
      Enum.each(not_run, &Printer.print_result/1)

      finish(
        [format_result, compile_result | not_run],
        started,
        reporting,
        config,
        "Compilation failed"
      )
    else
      # Phase 3: Analysis (parallel with streaming)
      Mix.shell().info("\nRunning analysis stages in parallel...\n")

      analysis_results = run_analysis_stages(config)
      all_results = [format_result, compile_result | analysis_results]

      finish(all_results, started, reporting, config, nil)
    end
  end

  # `--until-first-failure`: one stage at a time, cheapest first, stopping at the
  # first failure. Nothing runs in parallel here, which is the point: the run
  # exists to name the next thing to fix, and a stage that would have taken a
  # minute to also fail is a minute spent on something the caller is not going to
  # read yet.
  defp run_serially(config, started, reporting) do
    {stages, skipped} = serial_stages(config)
    Enum.each(skipped, &Printer.print_result/1)

    {ran, not_run} = run_until_failure(stages, config)

    stopped = Enum.map(not_run, &Stage.skipped(&1.name, "--until-first-failure", :run))
    Enum.each(stopped, &Printer.print_result/1)

    finish(skipped ++ ran ++ stopped, started, reporting, config, nil)
  end

  defp run_until_failure(stages, config) do
    Enum.reduce_while(stages, {[], stages}, fn stage, {ran, remaining} ->
      result = stage.run.(config)
      Printer.print_result(result)

      ran = ran ++ [result]
      remaining = tl(remaining)

      if result.status == :error, do: {:halt, {ran, remaining}}, else: {:cont, {ran, remaining}}
    end)
  end

  # Every stage of the run, runnable ones cheapest first. Unlike the phased path
  # this includes format and compile, because with no parallel phase to sit ahead
  # of they are just the two cheapest stages.
  defp serial_stages(config) do
    {stages, skipped} =
      config
      |> all_candidates()
      |> Enum.split_with(&is_nil(&1.skip))

    {Enum.sort_by(stages, &cost_index(&1.key)), Enum.map(skipped, &skipped_result/1)}
  end

  defp skipped_result(%{name: name, skip: {reason, kind}}) do
    Stage.skipped(name, reason, kind)
  end

  defp cost_index(key) do
    Enum.find_index(@cost_order, &(&1 == key)) || Enum.find_index(@cost_order, &(&1 == :custom))
  end

  # A stage that a profile or a `--skip` turned off is reported as skipped rather
  # than run. Format and compile have always run unconditionally, and they still
  # do unless something says otherwise.
  defp run_or_skip(config, key, name, run) do
    case Config.skip(config, key) do
      nil -> run.(config)
      {reason, kind} -> Stage.skipped(name, reason, kind)
    end
  end

  # One exit for every run: render the human verdict, emit the report, and
  # hand the verdict back. The report is built whether or not anyone asked for
  # it on disk, because `execute/1`'s caller reads it either way, and it is
  # written before the failure propagates so a caller still gets it.
  defp finish(results, started, reporting, config, message) do
    failures = Enum.filter(results, &(&1.status == :error))

    if failures != [] do
      Mix.shell().info("")
      display_failure_details(failures, reporting.device)
    else
      Mix.shell().info([:green, "\n✓ All quality checks passed!"])
    end

    report = Report.build(results, System.monotonic_time(:millisecond) - started, config)
    emit_report(report, reporting)

    failure =
      if failures != [] do
        message || "#{length(failures)} quality check(s) failed"
      end

    %{report: report, config: config, failure: failure}
  end

  defp emit_report(_report, %{format: :human, path: nil}), do: :ok

  defp emit_report(report, reporting) do
    json = Report.encode!(report)

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

      {writers, readers} = Enum.split_with(stages, &(&1.kind == :writer))

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

  defp run_stage(stage, config) do
    result = stage.run.(config)
    Printer.print_result(result)
    result
  end

  # Every stage is either run or reported as skipped with its reason. Tests run
  # unless something turned them off explicitly - a `--skip test` or a profile
  # that leaves them out - and quick mode narrows what they measure rather than
  # whether they run.
  defp build_analysis_stages(config) do
    candidates = candidate_stages(config) ++ [test_stage(config)]
    {stages, skipped} = Enum.split_with(candidates, &is_nil(&1.skip))

    {stages, Enum.map(skipped, &skipped_result/1)}
  end

  # Built-ins first, then the project's own stages, in declaration order. Both
  # kinds are the same shape from here on, which is why the writer/reader
  # split, the printer and the report need to know nothing about custom stages.
  defp candidate_stages(config) do
    builtin =
      Enum.map(@analysis_stages, fn {key, module, name} ->
        stage(
          key,
          name,
          Stage.kind(module, config),
          &module.run/1,
          stage_skip(config, key)
        )
      end)

    custom =
      Enum.map(Custom.stages(config), fn entry ->
        stage(
          Keyword.fetch!(entry, :key),
          Keyword.fetch!(entry, :name),
          Custom.kind(entry, config),
          Custom.runner(entry),
          Custom.skip(config, entry)
        )
      end)

    builtin ++ custom
  end

  # Format and compile are phases rather than analysis stages in the default run,
  # so they are only assembled as candidates for the serial path, which has no
  # phases to be ahead of.
  defp all_candidates(config) do
    [
      stage(:format, "Format", :writer, &Format.run/1, Config.skip(config, :format)),
      stage(:compile, "Compile", :writer, &Compile.run/1, Config.skip(config, :compile)),
      test_stage(config)
    ] ++ candidate_stages(config)
  end

  defp test_stage(config) do
    stage(
      :test,
      "Tests",
      Stage.kind(Test, config),
      &Test.run/1,
      Config.skip(config, :test)
    )
  end

  defp stage(key, name, kind, run, skip) do
    %{key: key, name: name, kind: kind, run: run, skip: skip}
  end

  # The stages of a run that stopped before the analysis phase: the ones that
  # would have run take the given reason, the rest keep their own. The skip is
  # a `:run` one - this run stopped early; a run whose compile passes checks
  # them.
  defp analysis_stages_not_run(config, reason) do
    {stages, skipped} = build_analysis_stages(config)

    skipped ++ Enum.map(stages, &Stage.skipped(&1.name, reason, :run))
  end

  defp stage_skip(config, :dialyzer) do
    case Config.skip(config, :dialyzer) do
      nil -> if Keyword.get(config, :quick, false), do: {"--quick", :run}
      skip -> skip
    end
  end

  defp stage_skip(config, stage), do: Config.skip(config, stage)

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
end
