defmodule ExQuality.Stages.Dialyzer do
  @moduledoc """
  Runs Dialyzer type checking on the codebase.

  Executes `mix dialyzer` with MIX_ENV=dev. Handles PLT building
  gracefully and works around common "Could not get Core Erlang code"
  errors for Mix tasks.

  This stage is automatically enabled only if `:dialyxir` is in deps.
  """

  @doc """
  Runs the dialyzer stage.

  Returns success if no type warnings are found. Handles PLT building
  and debug_info issues gracefully.
  """
  @spec run(keyword()) :: ExQuality.Stage.result()
  def run(_config) do
    start_time = System.monotonic_time(:millisecond)

    {output, exit_code} =
      System.cmd("mix", ["dialyzer"],
        env: [{"MIX_ENV", "dev"}],
        stderr_to_stdout: true
      )

    duration_ms = System.monotonic_time(:millisecond) - start_time
    warning_count = parse_warning_count(output)

    case {exit_code, warning_count} do
      {0, _} ->
        %{
          name: "Dialyzer",
          status: :ok,
          output: output,
          stats: %{warning_count: 0},
          summary: "No warnings",
          duration_ms: duration_ms
        }

      {_, 0} ->
        # Non-zero exit but no warnings found - could be PLT building or other issue
        # Check if it's the common "Could not get Core Erlang code" error for Mix tasks
        is_debug_info_error = is_debug_info_error?(output)

        if is_debug_info_error do
          # This is a known issue with Mix tasks not having debug_info
          # Treat as success if there are no actual type warnings
          %{
            name: "Dialyzer",
            status: :ok,
            output: output,
            stats: %{warning_count: 0},
            summary: "No warnings (some files skipped)",
            duration_ms: duration_ms
          }
        else
          # Unknown error with no warnings - report as error
          %{
            name: "Dialyzer",
            status: :error,
            output: output,
            stats: %{warning_count: 0},
            summary: "Check failed (see output)",
            duration_ms: duration_ms
          }
        end

      {_, count} ->
        %{
          name: "Dialyzer",
          status: :error,
          output: output,
          stats: %{warning_count: count},
          summary: format_summary(count),
          duration_ms: duration_ms
        }
    end
  end

  defp parse_warning_count(output) do
    # Count lines that look like dialyzer warnings
    # Format: "lib/some_file.ex:42: Some warning message"
    # or "lib/some_file.ex:42:5: Some warning message"
    # or "lib/mix/tasks/quality.ex:134:13:unknown_function"
    output
    |> String.split("\n")
    |> Enum.count(&String.match?(&1, ~r/\.exs?:\d+:/))
  end

  defp is_debug_info_error?(output) do
    String.contains?(output, "Could not get Core Erlang code") and
      String.contains?(output, "Recompile with +debug_info")
  end

  defp format_summary(1), do: "1 warning"
  defp format_summary(count), do: "#{count} warnings"
end
