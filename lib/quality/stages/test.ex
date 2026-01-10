defmodule Quality.Stages.Test do
  @moduledoc """
  Runs the test suite with optional coverage analysis.

  - Uses `mix coveralls` if `:excoveralls` is in deps
  - Uses `mix test` otherwise or in quick mode
  - Parses test count, pass/fail counts
  - Parses coverage percentage if available
  - Reads coverage threshold from coveralls config (single source of truth)

  In quick mode: runs `mix test` instead of `mix coveralls`
  (tests must pass, but coverage threshold is not enforced).
  """

  @doc """
  Runs the test stage.

  ## Config options

  - `quick` - Use `mix test` instead of `mix coveralls` (default: false)
  """
  @spec run(keyword()) :: Quality.Stage.result()
  def run(config) do
    start_time = System.monotonic_time(:millisecond)

    quick_mode = Keyword.get(config, :quick, false)
    coverage_available = Quality.Tools.available?(:coverage)

    # Use coveralls if available and not in quick mode
    use_coveralls = coverage_available and not quick_mode

    {command, args} =
      if use_coveralls do
        {"mix", ["coveralls"]}
      else
        {"mix", ["test"]}
      end

    {output, exit_code} =
      System.cmd(command, args,
        env: [{"MIX_ENV", "test"}],
        stderr_to_stdout: true
      )

    duration_ms = System.monotonic_time(:millisecond) - start_time
    stats = parse_test_stats(output, use_coveralls)

    case exit_code do
      0 ->
        %{
          name: "Tests",
          status: :ok,
          output: output,
          stats: stats,
          summary: format_success_summary(stats, use_coveralls),
          duration_ms: duration_ms
        }

      _error ->
        %{
          name: "Tests",
          status: :error,
          output: output,
          stats: stats,
          summary: format_failure_summary(stats, use_coveralls),
          duration_ms: duration_ms
        }
    end
  end

  defp parse_test_stats(output, use_coveralls) do
    stats = %{}

    # Parse test counts: "248 tests, 3 failures"
    # Also handles: "248 tests, 3 failures, 5 excluded"
    stats =
      case Regex.run(~r/(\d+) tests?, (\d+) failures?(?:, \d+ excluded)?/, output) do
        [_, total, failures] ->
          total = String.to_integer(total)
          failed = String.to_integer(failures)

          Map.merge(stats, %{
            test_count: total,
            passed_count: total - failed,
            failed_count: failed
          })

        _ ->
          stats
      end

    # Parse coverage if using coveralls: "[TOTAL]  85.2%"
    stats =
      if use_coveralls do
        case Regex.run(~r/\[TOTAL\]\s+(\d+\.?\d*)%/, output) do
          [_, coverage] ->
            Map.put(stats, :coverage, String.to_float(coverage))

          _ ->
            stats
        end
      else
        stats
      end

    # Try to read coverage threshold from coveralls config
    stats =
      if use_coveralls do
        threshold = read_coverage_threshold()
        if threshold, do: Map.put(stats, :coverage_required, threshold), else: stats
      else
        stats
      end

    stats
  end

  defp read_coverage_threshold do
    # Try to read from coveralls.json first
    case File.read("coveralls.json") do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, config} ->
            config["minimum_coverage"] || config["coverage_threshold"]

          _ ->
            nil
        end

      _ ->
        # Try to read from mix.exs project config
        case Mix.Project.get() do
          nil ->
            nil

          _module ->
            config = Mix.Project.config()
            test_coverage = Keyword.get(config, :test_coverage, [])

            Keyword.get(test_coverage, :minimum_coverage) ||
              Keyword.get(test_coverage, :threshold)
        end
    end
  end

  defp format_success_summary(stats, use_coveralls) do
    test_summary = format_test_counts(stats)

    if use_coveralls and stats[:coverage] != nil do
      "#{test_summary}, #{format_coverage(stats[:coverage])} coverage"
    else
      test_summary
    end
  end

  defp format_failure_summary(stats, use_coveralls) do
    if stats[:failed_count] && stats[:failed_count] > 0 do
      test_summary = "#{stats[:failed_count]} of #{stats[:test_count]} failed"

      if use_coveralls and stats[:coverage] != nil do
        "#{test_summary}, #{format_coverage(stats[:coverage])} coverage"
      else
        test_summary
      end
    else
      # Coverage failure
      if use_coveralls and stats[:coverage] != nil and stats[:coverage_required] != nil do
        "Coverage #{format_coverage(stats[:coverage])} (required: #{format_coverage(stats[:coverage_required])})"
      else
        "Tests failed"
      end
    end
  end

  defp format_test_counts(stats) do
    case {stats[:passed_count], stats[:test_count]} do
      {passed, total} when passed != nil and total != nil ->
        "#{passed} of #{total} passed"

      {nil, total} when total != nil ->
        "#{total} tests"

      _ ->
        "Tests passed"
    end
  end

  defp format_coverage(nil), do: "N/A"
  defp format_coverage(pct), do: "#{:erlang.float_to_binary(pct, decimals: 1)}%"
end
