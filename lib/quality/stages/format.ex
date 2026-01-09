defmodule Quality.Stages.Format do
  @moduledoc """
  Auto-fixes code formatting by running `mix format`.

  This stage always succeeds (format can't fail on valid Elixir code).
  Reports how many files were modified.

  This is the only stage that modifies code - all other stages are read-only.
  """

  @doc """
  Runs the format stage.

  First checks which files need formatting, then formats them.
  Returns a result with the list of formatted files.
  """
  @spec run(keyword()) :: Quality.Stage.result()
  def run(_config) do
    start_time = System.monotonic_time(:millisecond)

    # Get list of files that would change (for reporting)
    {check_output, check_exit} =
      System.cmd("mix", ["format", "--check-formatted"], stderr_to_stdout: true)

    files_to_format = parse_files_needing_format(check_output, check_exit)

    # Actually format the files
    {_output, _exit} = System.cmd("mix", ["format"], stderr_to_stdout: true)

    duration_ms = System.monotonic_time(:millisecond) - start_time

    summary =
      case length(files_to_format) do
        0 -> "No changes needed"
        1 -> "Formatted 1 file"
        n -> "Formatted #{n} files"
      end

    output =
      if files_to_format == [] do
        ""
      else
        Enum.join(files_to_format, "\n")
      end

    %{
      name: "Format",
      status: :ok,
      output: output,
      stats: %{files_formatted: length(files_to_format)},
      summary: summary,
      duration_ms: duration_ms
    }
  end

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
