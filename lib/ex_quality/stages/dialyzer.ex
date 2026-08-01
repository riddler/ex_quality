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
        # Non-zero exit but no warnings found - could be PLT building or other issue
        # Check if it's the common "Could not get Core Erlang code" error for Mix tasks
        if debug_info_error?(output) do
          # This is a known issue with Mix tasks not having debug_info
          # Treat as success if there are no actual type warnings
          summary = summary("No warnings", plt_built?, "some files skipped")

          result(output, :ok, [], summary, plt_built?, duration_ms)
        else
          # Unknown error with no warnings - report as error
          summary = summary("Check failed", plt_built?, "see output")

          result(output, :error, [], summary, plt_built?, duration_ms)
        end

      {_exit_code, findings} ->
        summary = summary(format_warnings(length(findings)), plt_built?)

        result(output, :error, findings, summary, plt_built?, duration_ms)
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
        file = Finding.relative_path(file)

        [
          %Finding{
            file: file,
            line: String.to_integer(line_no),
            column: position(column),
            app: Umbrella.app_for_path(file, apps),
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

  defp debug_info_error?(output) do
    String.contains?(output, "Could not get Core Erlang code") and
      String.contains?(output, "Recompile with +debug_info")
  end

  defp format_warnings(1), do: "1 warning"
  defp format_warnings(count), do: "#{count} warnings"
end
