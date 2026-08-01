defmodule ExQuality.Stages.Format do
  @moduledoc """
  Auto-fixes code formatting by running `mix format`.

  Reports how many files were modified.

  This is the only stage that modifies code - all other stages are read-only.

  ## Projects with no formatter

  `mix format` needs a `.formatter.exs` (or explicit patterns) and fails
  without one. That is a project that has never used the formatter, not a
  project with a problem, so the stage reports it as skipped rather than
  failing the run over a missing config file.

  ## When formatting fails

  `mix format` succeeds on any code it can parse, so the usual outcome is a
  pass. It does fail on a file with a syntax error, and the stage reports that
  rather than reading the file list out of the failed run: a `SyntaxError` line
  names no `.ex` file to count, so the stage used to print a green tick as the
  first line of a run on a broken file. Compile says the same thing moments
  later, but the run should not have claimed otherwise in the meantime.
  """

  @doc """
  Runs the format stage.

  First checks which files need formatting, then formats them.
  Returns a result with the list of formatted files, the tool's output when
  `mix format` itself failed, or a `:skipped` result when the project has no
  `.formatter.exs`.
  """
  @spec run(keyword()) :: ExQuality.Stage.result()
  def run(_config) do
    cond do
      ExQuality.Aliases.shadowing?("format") ->
        ExQuality.Aliases.shadowed("Format", "format")

      formatter_config?() ->
        format()

      true ->
        ExQuality.Stage.skipped("Format", "no .formatter.exs")
    end
  end

  # The same file `mix format` itself looks for, in the same place: the
  # directory the command runs in, which is the project root.
  defp formatter_config?, do: File.exists?(".formatter.exs")

  defp format do
    start_time = System.monotonic_time(:millisecond)

    # Get list of files that would change (for reporting)
    {check_output, check_exit} =
      System.cmd("mix", ["format", "--check-formatted"], stderr_to_stdout: true)

    files_to_format = parse_files_needing_format(check_output, check_exit)

    # Actually format the files
    {format_output, format_exit} = System.cmd("mix", ["format"], stderr_to_stdout: true)

    duration_ms = System.monotonic_time(:millisecond) - start_time

    result(files_to_format, format_output, format_exit, duration_ms)
  end

  defp result(files_to_format, _output, 0, duration_ms) do
    %{
      name: "Format",
      status: :ok,
      output: Enum.join(files_to_format, "\n"),
      stats: %{files_formatted: length(files_to_format)},
      summary: summary(length(files_to_format)),
      duration_ms: duration_ms
    }
  end

  # A failed `mix format` may still have rewritten the files it could parse, so
  # the count is reported alongside the failure rather than in place of it.
  defp result(files_to_format, output, _exit_code, duration_ms) do
    %{
      name: "Format",
      status: :error,
      output: output,
      stats: %{files_formatted: length(files_to_format)},
      summary: "mix format failed",
      duration_ms: duration_ms
    }
  end

  defp summary(0), do: "No changes needed"
  defp summary(1), do: "Formatted 1 file"
  defp summary(count), do: "Formatted #{count} files"

  # If check-formatted exits 0, no files need formatting
  defp parse_files_needing_format(_output, 0), do: []

  # If check-formatted exits non-zero, parse the file list
  defp parse_files_needing_format(output, _exit) do
    output
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.filter(fn line ->
      String.ends_with?(line, ".ex") or String.ends_with?(line, ".exs")
    end)
    |> Enum.reject(&(&1 == ""))
  end
end
