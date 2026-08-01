defmodule ExQuality.Stages.Dialyzer do
  @moduledoc """
  Runs Dialyzer type checking on the codebase.

  Executes `mix dialyzer --format short --format dialyxir` with MIX_ENV=dev.
  Handles PLT building gracefully and works around common "Could not get Core
  Erlang code" errors for Mix tasks.

  This stage is automatically enabled only if `:dialyxir` is in deps.

  ## Why both formats

  dialyxir's default output spreads one warning over a block of explanation,
  so counting warnings meant counting lines that looked like `file.ex:12:`,
  which also counts PLT chatter and any explanation that names a second file.
  `--format short` puts each warning on one line
  (`lib/user.ex:42:5:no_return Function create/1 has no local return.`), so the
  count is the number of findings and each one carries the warning name.

  dialyxir takes `--format` more than once and prints each warning in every
  format asked for, so the long explanation is asked for too and stays in the
  stage's `output`. It is what a reader falls back to when the short line is
  not enough, and what the JSON report carries for a stage that parsed nothing.
  The explanation's own header line ends at the warning name, with no message
  after it, so it never parses as a second finding for the same warning.

  ## PLT building

  Dialyzer analyses against a PLT, and building one on a cold checkout or a
  fresh CI container takes minutes. The stage prints
  `⋯ Dialyzer: building PLT (this is a one-time cost)` as soon as dialyxir
  starts, rather than leaving the wait to look like a hang, and says so again
  in its summary (`No warnings (PLT built this run)`) because the duration
  otherwise reads as the cost of every run.

  A build is reported, not penalised: the analysis that follows one is as good
  as any other, so the stage still passes or fails on its warnings alone.
  `mix quality.plt` is the way to pay for the build outside the run.

  ## Analyses that never ran

  `--no-compile` assumes the beams hold still. If something rewrites them while
  dialyzer is reading them, dialyzer stops with
  `Could not get Core Erlang code for: ... Recompile with +debug_info` and
  reports nothing at all.

  That is the same message a genuine no-debug_info dependency produces, and
  that one is worth passing over. The two are told apart by whether the
  analysis reached its own summary: dialyxir prints `Total errors: N` when it
  finished, even for N = 0. No summary means the analysis did not complete, and
  a stage that parsed zero findings because it never looked is not a stage that
  passed.

  ## Umbrellas

  dialyxir prints paths relative to each child app while running one analysis
  from the umbrella root, and there are no `==> app` headers to attribute from.
  A path like `lib/user.ex` therefore does not open from where the report was
  generated. Each one is resolved against the child apps by existence: exactly
  one match rewrites the path and names the app, and anything else is left
  alone rather than guessed at.
  """

  alias ExQuality.Finding
  alias ExQuality.OutputCollector
  alias ExQuality.Plt
  alias ExQuality.Printer
  alias ExQuality.Umbrella

  # One warning, one line: `file:line[:column]:warning_name message`. The
  # warning name is what tells a warning apart from the tool's own chatter,
  # which never carries one.
  @warning_regex ~r/^([^\s:]+):(\d+)(?::(\d+))?:([a-z_]+)\s+(.+)$/

  @doc """
  Runs the dialyzer stage.

  Returns success if no type warnings are found. Handles PLT building
  and debug_info issues gracefully.
  """
  @spec run(keyword()) :: ExQuality.Stage.result()
  def run(_config) do
    start_time = System.monotonic_time(:millisecond)

    {output, exit_code} = run_dialyzer()

    duration_ms = System.monotonic_time(:millisecond) - start_time
    findings = parse_findings(output)
    plt_built? = Plt.built?(output)

    case {exit_code, findings} do
      {0, _findings} ->
        result(output, :ok, [], summary("No warnings", plt_built?), plt_built?, duration_ms)

      {_exit_code, []} ->
        empty_result(output, plt_built?, duration_ms)

      {_exit_code, findings} ->
        summary = summary(format_warnings(length(findings)), plt_built?)

        result(output, :error, findings, summary, plt_built?, duration_ms)
    end
  end

  # A non-zero exit with nothing parsed is either "a few files had no
  # debug_info", which is fine, or "the analysis never ran", which is not. The
  # summary line dialyxir prints when it finishes is what tells them apart.
  defp empty_result(output, plt_built?, duration_ms) do
    cond do
      debug_info_error?(output) and analysis_completed?(output) ->
        summary = summary("No warnings", plt_built?, "some files skipped")

        result(output, :ok, [], summary, plt_built?, duration_ms)

      debug_info_error?(output) ->
        summary =
          summary("Analysis did not complete", plt_built?, "build changed under it? see output")

        result(output, :error, [], summary, plt_built?, duration_ms)

      true ->
        summary = summary("Check failed", plt_built?, "see output")

        result(output, :error, [], summary, plt_built?, duration_ms)
    end
  end

  # Output is streamed into a collector rather than captured wholesale, so the
  # PLT build can be announced while dialyxir is still in it.
  defp run_dialyzer do
    collector = OutputCollector.new(on_line: Plt.build_watcher(&announce_plt_build/0))

    {_into, exit_code} =
      System.cmd("mix", ["dialyzer", "--no-compile", "--format", "short", "--format", "dialyxir"],
        env: [{"MIX_ENV", "dev"}],
        stderr_to_stdout: true,
        into: collector
      )

    {OutputCollector.get_output(collector), exit_code}
  end

  defp announce_plt_build do
    Printer.print_message("⋯ Dialyzer: #{Plt.message()}")
  end

  defp result(output, status, findings, summary, plt_built?, duration_ms) do
    %{
      name: "Dialyzer",
      status: status,
      output: output,
      findings: findings,
      stats: stats(length(findings), plt_built?),
      summary: summary,
      duration_ms: duration_ms
    }
  end

  # `plt_built` is carried only when it happened: a key that is false on every
  # warm run tells a reader nothing.
  defp stats(warning_count, false), do: %{warning_count: warning_count}
  defp stats(warning_count, true), do: %{warning_count: warning_count, plt_built: true}

  defp summary(headline, plt_built?, note \\ nil) do
    notes = Enum.reject([note, plt_note(plt_built?)], &is_nil/1)

    case notes do
      [] -> headline
      notes -> "#{headline} (#{Enum.join(notes, ", ")})"
    end
  end

  defp plt_note(true), do: "PLT built this run"
  defp plt_note(false), do: nil

  # Every warning is a line of its own, so a line that does not parse is not a
  # warning: it is the tool talking about the PLT or about itself.
  defp parse_findings(output) do
    # Read the umbrella layout once rather than once per finding.
    apps = Umbrella.apps_paths()

    output
    |> String.split("\n")
    |> Enum.flat_map(&finding(&1, apps))
    |> Finding.sort()
  end

  defp finding(line, apps) do
    case Regex.run(@warning_regex, line) do
      [_match, file, line_no, column, warning, message] ->
        {file, app} = file |> Finding.relative_path() |> locate(apps)

        [
          %Finding{
            file: file,
            line: String.to_integer(line_no),
            column: position(column),
            app: app,
            # Every dialyzer warning fails the stage, so none of them is
            # informational.
            severity: :error,
            check: warning,
            message: message,
            raw: line
          }
        ]

      _no_match ->
        []
    end
  end

  # A warning with no column matches with the column group empty.
  defp position(""), do: nil
  defp position(column), do: String.to_integer(column)

  # A path that already names its app is taken as it stands. One that does not
  # is an app-relative path from an umbrella run, and the app it belongs to is
  # the one that has the file. Two apps with the same relative path is
  # ambiguous, and a wrong app is worse than none, so it is left alone.
  defp locate(file, apps) do
    case Umbrella.app_for_path(file, apps) do
      nil -> resolve_in_apps(file, apps)
      app -> {file, app}
    end
  end

  defp resolve_in_apps(file, apps) do
    case Enum.filter(apps, fn {_app, path} -> File.exists?(Path.join(path, file)) end) do
      [{app, path}] -> {Path.join(path, file), app}
      _none_or_many -> {file, nil}
    end
  end

  defp debug_info_error?(output) do
    String.contains?(output, "Could not get Core Erlang code") and
      String.contains?(output, "Recompile with +debug_info")
  end

  # dialyxir closes a completed analysis with its own tally, whatever the tally
  # is. Its absence is the difference between "found nothing" and "never ran".
  defp analysis_completed?(output), do: String.contains?(output, "Total errors:")

  defp format_warnings(1), do: "1 warning"
  defp format_warnings(count), do: "#{count} warnings"
end
