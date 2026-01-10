defmodule ExQuality.Stages.Doctor do
  @moduledoc """
  Checks documentation coverage using the doctor package.

  Validates @moduledoc presence, function docs, and typespecs
  against configured thresholds.

  This stage is automatically enabled only if `:doctor` is in deps.
  """

  @doc """
  Runs the doctor stage.

  ## Config options

  - `summary_only` - Only show summary, not detailed report (default: false)
  """
  @spec run(keyword()) :: ExQuality.Stage.result()
  def run(config) do
    start_time = System.monotonic_time(:millisecond)

    doctor_config = Keyword.get(config, :doctor, [])
    args = build_args(doctor_config)

    {output, exit_code} =
      System.cmd("mix", args,
        env: [{"MIX_ENV", "dev"}],
        stderr_to_stdout: true
      )

    duration_ms = System.monotonic_time(:millisecond) - start_time
    stats = parse_doctor_output(output)

    if exit_code == 0 do
      %{
        name: "Doctor",
        status: :ok,
        output: output,
        stats: stats,
        summary: format_summary(stats),
        duration_ms: duration_ms
      }
    else
      %{
        name: "Doctor",
        status: :error,
        output: output,
        stats: stats,
        summary: "Documentation coverage below threshold",
        duration_ms: duration_ms
      }
    end
  end

  defp build_args(doctor_config) do
    args = ["doctor", "--raise"]

    if Keyword.get(doctor_config, :summary_only, false) do
      args ++ ["--summary"]
    else
      args
    end
  end

  defp parse_doctor_output(output) do
    # Try to parse coverage percentages from doctor output
    # Doctor typically shows output like:
    # "Doc coverage: 85.0%"
    # Or in the report: "Module: 12/15 (80.0%)"

    case Regex.run(~r/Doc coverage:\s+(\d+\.?\d*)%/, output) do
      [_, coverage] ->
        %{doc_coverage: String.to_float(coverage)}

      _ ->
        # Try alternative format
        case Regex.run(~r/(\d+\.?\d*)%.*coverage/i, output) do
          [_, coverage] ->
            %{doc_coverage: String.to_float(coverage)}

          _ ->
            %{}
        end
    end
  end

  defp format_summary(stats) do
    case stats[:doc_coverage] do
      nil -> "Passed"
      pct -> "#{:erlang.float_to_binary(pct, decimals: 1)}% documented"
    end
  end
end
