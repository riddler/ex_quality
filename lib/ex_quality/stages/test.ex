defmodule ExQuality.Stages.Test do
  @moduledoc """
  Runs the test suite with optional coverage analysis.

  - Uses `mix coveralls` if `:excoveralls` is in deps
  - Uses `mix test --cover` if it is not, and the project asks for coverage
  - Uses `mix test` otherwise, and always in quick mode
  - Parses test count, pass/fail counts
  - Parses coverage percentage if available
  - Reads the coverage threshold from the tool's own config (single source of
    truth), whichever of the two tools is in use

  In quick mode: runs `mix test`
  (tests must pass, but coverage threshold is not enforced).

  ## Native coverage

  Elixir has shipped coverage since 1.11, so a project without `:excoveralls`
  is not a project without coverage. `mix test --cover` is used for those,
  reading `test_coverage: [summary: [threshold: N]]` from `mix.exs` the same way
  the built-in tool does.

  It is used only when the project sets that threshold, or asks for coverage
  explicitly with `test: [coverage: true]` in `.quality.exs`. Elixir's built-in
  threshold defaults to 90% whether or not a project has ever thought about
  coverage, and turning a green run red over a number nobody chose is not a
  gate anyone asked for. A stated threshold is the project saying it wants one.

  ## Umbrellas

  An umbrella `mix test` prints one summary line per app, so every summary is
  read and summed rather than only the first. Reporting the first app's numbers
  as the suite's is worse than reporting none: a confident, specific, false
  count ("3 of 12 failed" when the truth is "3 of 4,180 failed") reads as more
  trustworthy than no count at all.

  Apps with failures are named in the summary. Apps that passed are not, since
  the failing ones are what a reader acts on.

  Native coverage in an umbrella is measured in two commands, because a per-app
  `mix test --cover` only sees its own app's modules: a module exercised by
  another app's tests reads as 0%. So the run exports instead
  (`--export-coverage`), and `mix test.coverage` aggregates the exports into one
  table and one total.

  ## Findings

  A failing test is the most common thing a run has to hand off, so each one is
  parsed into a finding carrying the file, the line the test is defined at, the
  app, the test module and the assertion message. The alternative is 30 KB of
  run log with one failure buried in it.

  The failure block's own `stacktrace:` lines are relative to the app, while
  the header line under the test's name is relative to the umbrella root, so
  the header line is what is read: a path that does not open from where the
  report was generated cannot be routed anywhere.

  The parse is used only when it accounts for every failure the suite counted.
  Three findings for four failures would read as the complete list, which is
  worse than showing the log; a short parse falls back to `output` in full.

  A failing coverage check reports the modules under the threshold, not the
  whole table. A 400-module umbrella prints 400 rows; the handful below the line
  are the ones a reader acts on. Modules are reported only when the run actually
  failed on coverage, because the threshold applies to the total: a passing run
  can hold a low module and there is nothing to do about it.
  """

  alias ExQuality.Aliases
  alias ExQuality.Finding
  alias ExQuality.Umbrella

  # Elixir's documented aggregation workflow names the export "default", and
  # `mix test.coverage` imports whatever it finds in each app's cover directory.
  @export_name "default"

  @doc """
  Runs the test stage.

  ## Config options

  - `quick` - Use `mix test` with no coverage at all (default: false)
  - `test.args` - Extra arguments for the test command (default: `[]`)
  - `test.coverage` - `:auto` (use the project's config) | `true` (always
    measure) | `false` (never measure) (default: `:auto`)
  """
  @spec run(keyword()) :: ExQuality.Stage.result()
  def run(config) do
    mode = coverage_mode(config)

    if aggregating?(mode) and Aliases.shadowing?("test.coverage") do
      Aliases.shadowed("Tests", "test.coverage")
    else
      test(config, mode)
    end
  end

  # A `test:` alias is near-universal and running it is correct: it does the
  # setup the suite needs. `mix test.coverage` is pure aggregation, so an alias
  # on that one runs the whole suite a second time before aggregating, and the
  # only trace is a doubled test count and a doubled wall clock.
  defp aggregating?(mode), do: mode == :native and Umbrella.umbrella?()

  defp test(config, mode) do
    start_time = System.monotonic_time(:millisecond)

    test_args = config |> Keyword.get(:test, []) |> Keyword.get(:args, [])

    {output, exit_code} = run_tests(mode, test_args)

    duration_ms = System.monotonic_time(:millisecond) - start_time
    %{stats: stats, findings: findings} = analyze(output, mode)

    %{
      name: "Tests",
      status: if(exit_code == 0, do: :ok, else: :error),
      output: output,
      findings: findings,
      stats: stats,
      summary: summary(stats, mode, exit_code),
      duration_ms: duration_ms
    }
  end

  # `:coveralls` and `:native` differ only in which tool measures; `:plain`
  # means nothing measures.
  defp coverage_mode(config) do
    test_config = Keyword.get(config, :test, [])
    requested = Keyword.get(test_config, :coverage, :auto)

    cond do
      Keyword.get(config, :quick, false) -> :plain
      requested == false -> :plain
      ExQuality.Tools.available?(:coverage) -> :coveralls
      not ExQuality.Tools.available?(:native_coverage) -> :plain
      requested == true -> :native
      read_coverage_threshold(:native) != nil -> :native
      true -> :plain
    end
  end

  defp run_tests(:coveralls, args), do: mix(["coveralls" | args])

  defp run_tests(:native, args) do
    if Umbrella.umbrella?() do
      run_umbrella_coverage(args)
    else
      mix(["test", "--cover" | args])
    end
  end

  defp run_tests(_plain, args), do: mix(["test" | args])

  # Exporting suppresses the summary and the threshold check, so the aggregate
  # run is where coverage is decided. A failing suite skips it: mix stops at the
  # first failing app, so the exports are incomplete and any total drawn from
  # them would be a number about a run that did not finish.
  defp run_umbrella_coverage(args) do
    {output, exit_code} = mix(["test", "--cover", "--export-coverage", @export_name | args])

    if exit_code == 0 do
      {aggregate, aggregate_code} = mix(["test.coverage"])
      {output <> aggregate, aggregate_code}
    else
      {output, exit_code}
    end
  end

  defp mix(args) do
    System.cmd("mix", args, env: [{"MIX_ENV", "test"}], stderr_to_stdout: true)
  end

  # Each app's output is preceded by "==> app_name", so the app a summary line
  # belongs to is whichever header came before it. A single-app project has no
  # headers at all and every entry is attributed to nil.
  @app_regex ~r/^==>\s+(\S+)\s*$/
  # "248 tests, 3 failures", possibly followed by ", 5 excluded"
  @counts_regex ~r/(\d+) tests?, (\d+) failures?/
  # ExCoveralls: "[TOTAL]  85.2%"
  @coverage_regex ~r/\[TOTAL\]\s+(\d+\.?\d*)%/
  # Built-in coverage prints a "Percentage | Module" table closed by a "Total"
  # row, then names the threshold it enforced only when the check failed.
  @native_total_regex ~r/^\s*(\d+\.?\d*)%\s*\|\s*Total\s*$/
  @native_module_regex ~r/^\s*(\d+\.?\d*)%\s*\|\s*(\S+)\s*$/
  @native_threshold_regex ~r/^\s*Threshold:\s+(\d+\.?\d*)%/

  defp analyze(output, mode) do
    scan = scan_output(output)

    stats =
      %{}
      |> merge_test_counts(scan.tests)
      |> merge_coverage(scan, mode)

    findings = failure_findings(output, stats) ++ findings(stats, scan)

    %{stats: stats, findings: Finding.sort(findings)}
  end

  # Walks the output once, attributing every summary line to the app whose
  # header preceded it.
  defp scan_output(output) do
    output
    |> String.split("\n")
    |> Enum.reduce(
      %{app: nil, tests: [], coverage: [], modules: [], threshold: nil},
      &scan_line/2
    )
    |> Map.update!(:tests, &Enum.reverse/1)
    |> Map.update!(:coverage, &Enum.reverse/1)
    |> Map.update!(:modules, &Enum.reverse/1)
  end

  defp scan_line(line, acc) do
    cond do
      match = Regex.run(@app_regex, line) ->
        %{acc | app: Enum.at(match, 1)}

      match = Regex.run(@counts_regex, line) ->
        [_line, total, failed] = match

        entry = %{
          app: acc.app,
          total: String.to_integer(total),
          failed: String.to_integer(failed)
        }

        %{acc | tests: [entry | acc.tests]}

      match = Regex.run(@coverage_regex, line) ->
        add_coverage(acc, Enum.at(match, 1))

      match = Regex.run(@native_total_regex, line) ->
        add_coverage(acc, Enum.at(match, 1))

      match = Regex.run(@native_module_regex, line) ->
        [_line, percentage, module] = match
        entry = %{app: acc.app, module: module, coverage: to_float(percentage), raw: line}
        %{acc | modules: [entry | acc.modules]}

      match = Regex.run(@native_threshold_regex, line) ->
        %{acc | threshold: to_float(Enum.at(match, 1))}

      true ->
        acc
    end
  end

  defp add_coverage(acc, percentage) do
    %{acc | coverage: [%{app: acc.app, coverage: to_float(percentage)} | acc.coverage]}
  end

  # ExUnit opens each failure with a numbered header naming the test and its
  # module, and follows it immediately with the file and line the test is
  # defined at.
  @failure_header_regex ~r/^\s*\d+\)\s+(\w+)\s+(.+?)\s+\(([A-Z]\S*)\)\s*$/
  @failure_location_regex ~r/^\s*(\S+\.exs?):(\d+)\s*$/
  # Everything ExUnit prints about *how* the assertion failed rather than
  # *what* went wrong. The lines before these are the message.
  @failure_detail_regex ~r/^\s*(code|stacktrace|left|right|arguments|The following output was logged):/

  # A failing test is the most common thing a run has to hand off, so it is
  # parsed into a finding a caller can route rather than left in 30 KB of run
  # log. The whole log is still carried in `output`.
  #
  # Only a parse that accounts for every failure the suite reported is used. A
  # partial one would render three findings for four failures and read as the
  # complete list, which is worse than showing the log.
  defp failure_findings(output, %{failed_count: failed}) when failed > 0 do
    apps = Umbrella.apps_paths()

    findings =
      output
      |> String.split("\n")
      |> Enum.reduce(%{state: :scanning, failures: []}, &failure_line/2)
      |> close_failure()
      |> Map.fetch!(:failures)
      |> Enum.reverse()
      |> Enum.map(&failure_finding(&1, apps))

    if length(findings) == failed, do: findings, else: []
  end

  defp failure_findings(_output, _stats), do: []

  defp failure_line(line, %{state: :scanning} = acc) do
    case Regex.run(@failure_header_regex, line) do
      [_line, kind, name, module] ->
        failure = %{
          kind: kind,
          name: name,
          module: module,
          file: nil,
          line: nil,
          message: [],
          raw: [line]
        }

        %{acc | state: failure}

      nil ->
        acc
    end
  end

  # The location is on the line right after the header. Anything else there
  # means this was not a failure block after all.
  defp failure_line(line, %{state: %{file: nil} = failure} = acc) do
    case Regex.run(@failure_location_regex, line) do
      [_line, file, number] ->
        %{acc | state: %{failure | file: file, line: String.to_integer(number)}}

      nil ->
        %{acc | state: :scanning}
    end
  end

  defp failure_line(line, %{state: failure} = acc) when is_map(failure) do
    cond do
      Regex.match?(@failure_detail_regex, line) ->
        close_failure(%{acc | state: %{failure | raw: [line | failure.raw]}})

      String.trim(line) == "" ->
        close_failure(acc)

      true ->
        message = [String.trim(line) | failure.message]
        %{acc | state: %{failure | message: message, raw: [line | failure.raw]}}
    end
  end

  # A block with no location never became a failure, so there is nothing to
  # close; the reduce just returns to scanning.
  defp close_failure(%{state: :scanning} = acc), do: acc

  defp close_failure(%{state: %{file: nil}} = acc), do: %{acc | state: :scanning}

  defp close_failure(%{state: failure} = acc) do
    %{acc | state: :scanning, failures: [failure | acc.failures]}
  end

  defp failure_finding(failure, apps) do
    file = Finding.relative_path(failure.file)

    %Finding{
      file: file,
      line: failure.line,
      app: Umbrella.app_for_path(file, apps),
      severity: :error,
      check: failure.module,
      message: describe_failure(failure),
      raw: failure.raw |> Enum.reverse() |> Enum.join("\n")
    }
  end

  defp describe_failure(%{name: name, message: []}), do: name

  defp describe_failure(%{name: name, message: message}) do
    "#{name}: #{message |> Enum.reverse() |> Enum.join(" ")}"
  end

  defp merge_test_counts(stats, []), do: stats

  defp merge_test_counts(stats, tests) do
    total = tests |> Enum.map(& &1.total) |> Enum.sum()
    failed = tests |> Enum.map(& &1.failed) |> Enum.sum()

    Map.merge(stats, %{
      test_count: total,
      passed_count: total - failed,
      failed_count: failed,
      failures_by_app: failures_by_app(tests)
    })
  end

  defp failures_by_app(tests) do
    for %{app: app, failed: failed} <- tests, app != nil, failed > 0, do: {app, failed}
  end

  defp merge_coverage(stats, _scan, :plain), do: stats

  defp merge_coverage(stats, scan, mode) do
    stats
    |> merge_coverage_percentages(scan.coverage)
    |> merge_coverage_threshold(scan.threshold, mode)
  end

  defp merge_coverage_percentages(stats, []), do: stats

  defp merge_coverage_percentages(stats, [%{coverage: coverage}]) do
    Map.put(stats, :coverage, coverage)
  end

  # Several totals means several apps were measured separately. The lowest is
  # the one that fails a threshold, so it leads, with the rest kept alongside
  # it rather than averaged into a number no tool reported.
  defp merge_coverage_percentages(stats, entries) do
    Map.merge(stats, %{
      coverage: entries |> Enum.map(& &1.coverage) |> Enum.min(),
      coverage_by_app: for(%{app: app, coverage: pct} <- entries, app != nil, do: {app, pct})
    })
  end

  # The threshold the tool printed is what it actually enforced, so it wins over
  # the one read back from config. It is only printed on a failure, which is the
  # one case where being exact matters.
  defp merge_coverage_threshold(stats, reported, mode) do
    case reported || read_coverage_threshold(mode) do
      nil -> stats
      threshold -> Map.put(stats, :coverage_required, threshold)
    end
  end

  defp to_float(value) do
    {number, _rest} = Float.parse(value)
    number
  end

  # ExCoveralls keeps its threshold in coveralls.json, or in mix.exs for a
  # project that configures it there. The built-in tool reads exactly one key,
  # so that is the only one looked at for it: reading an excoveralls key would
  # report a threshold nothing enforces.
  defp read_coverage_threshold(:native), do: native_threshold(project_config(:test_coverage, []))

  defp read_coverage_threshold(_coveralls) do
    coveralls_json_threshold() || coveralls_project_threshold()
  end

  defp native_threshold(test_coverage) do
    case Keyword.get(test_coverage, :summary, []) do
      summary when is_list(summary) -> Keyword.get(summary, :threshold)
      _disabled -> nil
    end
  end

  defp coveralls_project_threshold do
    test_coverage = project_config(:test_coverage, [])

    Keyword.get(test_coverage, :minimum_coverage) || Keyword.get(test_coverage, :threshold)
  end

  # `minimum_coverage` lives under `coverage_options` in a coveralls.json
  # written by excoveralls itself; older ExQuality releases only looked at the
  # top level, where it never is.
  defp coveralls_json_threshold do
    with {:ok, contents} <- File.read("coveralls.json"),
         {:ok, config} <- Jason.decode(contents) do
      options = Map.get(config, "coverage_options", %{})

      config["minimum_coverage"] || config["coverage_threshold"] ||
        options["minimum_coverage"] || options["coverage_threshold"]
    else
      _error -> nil
    end
  end

  defp project_config(key, default) do
    case Mix.Project.get() do
      nil -> default
      _module -> Keyword.get(Mix.Project.config(), key, default)
    end
  end

  # Only a run that failed on coverage reports modules, and only the ones under
  # the threshold. The threshold is a statement about the total, so a passing
  # run's low modules are not something a reader has an action to take on.
  defp findings(%{coverage: coverage, coverage_required: required}, scan)
       when coverage < required do
    apps = Umbrella.apps_paths()

    scan.modules
    |> Enum.filter(&(&1.coverage < required))
    |> Enum.map(&finding(&1, required, apps))
    |> Finding.sort()
  end

  defp findings(_stats, _scan), do: []

  defp finding(entry, required, apps) do
    source = module_source(entry.module)

    %Finding{
      file: source || entry.module,
      app: Umbrella.app_for_path(source, apps),
      severity: :error,
      message:
        "#{entry.module} is #{percentage(entry.coverage)} covered " <>
          "(threshold #{percentage(required)})",
      raw: entry.raw
    }
  end

  # The table names modules, but every other stage's findings name a file, and
  # an app can only be attributed from a path. The source is recorded in the
  # compiled beam, so it is read from there rather than by loading the module,
  # which is compiled into the test environment and not this one.
  defp module_source(module) do
    [test_build_path(), "lib", "*", "ebin", beam_name(module)]
    |> Path.join()
    |> Path.wildcard()
    |> List.first()
    |> beam_source()
  end

  defp beam_name(":" <> erlang_module), do: "#{erlang_module}.beam"
  defp beam_name(module), do: "Elixir.#{module}.beam"

  defp beam_source(nil), do: nil

  defp beam_source(beam) do
    with {:ok, {_module, [compile_info: info]}} <-
           :beam_lib.chunks(String.to_charlist(beam), [:compile_info]),
         source when is_list(source) <- Keyword.get(info, :source) do
      source |> List.to_string() |> Path.relative_to_cwd()
    else
      _error -> nil
    end
  end

  # The stage runs in the dev environment and the tests ran in test, so the
  # beams are in the sibling build directory rather than this one's.
  defp test_build_path do
    case Mix.Project.get() do
      nil -> Path.join("_build", "test")
      _module -> Mix.Project.build_path() |> Path.dirname() |> Path.join("test")
    end
  end

  defp summary(stats, mode, 0), do: format_success_summary(stats, mode)
  defp summary(stats, mode, _error), do: format_failure_summary(stats, mode)

  defp format_success_summary(stats, mode) do
    test_summary = format_test_counts(stats)

    if mode != :plain and stats[:coverage] != nil do
      "#{test_summary}, #{format_coverage_summary(stats)}"
    else
      test_summary
    end
  end

  defp format_failure_summary(stats, mode) do
    if stats[:failed_count] && stats[:failed_count] > 0 do
      test_summary =
        "#{format_count(stats[:failed_count])} of #{format_count(stats[:test_count])} failed" <>
          format_failing_apps(stats[:failures_by_app])

      if mode != :plain and stats[:coverage] != nil do
        "#{test_summary}, #{format_coverage_summary(stats)}"
      else
        test_summary
      end
    else
      format_coverage_failure(stats, mode)
    end
  end

  defp format_coverage_failure(stats, mode) do
    if mode != :plain and stats[:coverage] != nil and stats[:coverage_required] != nil do
      "Coverage #{percentage(stats[:coverage])} (required: #{percentage(stats[:coverage_required])})"
    else
      "Tests failed"
    end
  end

  defp format_test_counts(stats) do
    case {stats[:passed_count], stats[:test_count]} do
      {passed, total} when passed != nil and total != nil ->
        "#{format_count(passed)} of #{format_count(total)} passed"

      {nil, total} when total != nil ->
        "#{format_count(total)} tests"

      _ ->
        "Tests passed"
    end
  end

  # Only the failing apps are named: they are the ones a reader acts on, and a
  # ten-app umbrella would otherwise spend most of the line on zeroes.
  defp format_failing_apps(nil), do: ""
  defp format_failing_apps([]), do: ""

  defp format_failing_apps(failures) do
    " (" <> Enum.map_join(failures, ", ", fn {app, count} -> "#{app}: #{count}" end) <> ")"
  end

  # An umbrella measured app by app has no single total, so the headline says
  # which of the several numbers it is rather than implying a suite-wide one.
  defp format_coverage_summary(%{coverage_by_app: [_first, _second | _rest] = by_app} = stats) do
    "#{percentage(stats[:coverage])} coverage (lowest of #{length(by_app)} apps)"
  end

  defp format_coverage_summary(stats), do: "#{percentage(stats[:coverage])} coverage"

  defp percentage(nil), do: "N/A"
  defp percentage(pct) when is_integer(pct), do: percentage(pct / 1)
  defp percentage(pct), do: "#{:erlang.float_to_binary(pct, decimals: 1)}%"

  # Thousands separators, because suite sizes in an umbrella reach five digits
  # and "4180" is harder to read at a glance than "4,180".
  defp format_count(nil), do: "?"

  defp format_count(count) do
    count
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
    |> String.reverse()
  end
end
