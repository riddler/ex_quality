defmodule Quality.Stages.Dependencies do
  @moduledoc """
  Checks dependency health by running:

  1. `mix deps.unlock --check-unused` - Detects dependencies in mix.lock
     that are no longer referenced in mix.exs
  2. `mix deps.audit` - Scans dependencies for known security vulnerabilities
     using the mix_audit package

  Both checks run in parallel and results are combined.

  This stage always runs (unused dependency check). The security audit
  is automatically enabled only if `:mix_audit` is in deps.
  """

  @doc """
  Runs the dependencies stage.

  ## Config options

  - `check_unused` - Check for unused dependencies (default: true)
  - `audit` - Run security audit if available (default: :auto)
  - `audit_available` - Whether mix_audit is available (set by auto-detection)
  """
  @spec run(keyword()) :: Quality.Stage.result()
  def run(config) do
    start_time = System.monotonic_time(:millisecond)

    deps_config = Keyword.get(config, :dependencies, [])

    # Check if audit should run
    audit_available = Keyword.get(deps_config, :audit_available, false)
    audit_enabled = Keyword.get(deps_config, :audit, :auto)
    should_audit = audit_enabled == true or (audit_enabled == :auto and audit_available)

    # Check if unused check should run
    check_unused = Keyword.get(deps_config, :check_unused, true)

    # Run both checks in parallel if both enabled
    unused_task =
      if check_unused do
        Task.async(fn -> check_unused_deps() end)
      else
        nil
      end

    audit_task =
      if should_audit do
        Task.async(fn -> check_deps_audit() end)
      else
        nil
      end

    unused_result = if unused_task, do: Task.await(unused_task, :infinity), else: {:ok, ""}
    audit_result = if audit_task, do: Task.await(audit_task, :infinity), else: {:ok, ""}

    duration_ms = System.monotonic_time(:millisecond) - start_time

    combine_results(unused_result, audit_result, should_audit, duration_ms)
  end

  defp check_unused_deps do
    {output, exit_code} =
      System.cmd("mix", ["deps.unlock", "--check-unused"],
        env: [{"MIX_ENV", "dev"}],
        stderr_to_stdout: true
      )

    if exit_code == 0, do: {:ok, output}, else: {:error, output}
  end

  defp check_deps_audit do
    {output, exit_code} =
      System.cmd("mix", ["deps.audit"],
        env: [{"MIX_ENV", "dev"}],
        stderr_to_stdout: true
      )

    if exit_code == 0, do: {:ok, output}, else: {:error, output}
  end

  defp combine_results(unused_result, audit_result, audit_ran?, duration_ms) do
    case {unused_result, audit_result} do
      {{:ok, _}, {:ok, _}} ->
        summary = build_success_summary(audit_ran?)

        %{
          name: "Dependencies",
          status: :ok,
          output: "",
          stats: %{},
          summary: summary,
          duration_ms: duration_ms
        }

      {{:error, unused_output}, {:ok, _}} ->
        %{
          name: "Dependencies",
          status: :error,
          output: unused_output,
          stats: %{unused_deps: parse_unused_count(unused_output)},
          summary: "Unused dependencies detected",
          duration_ms: duration_ms
        }

      {{:ok, _}, {:error, audit_output}} ->
        stats = parse_audit_output(audit_output)

        %{
          name: "Dependencies",
          status: :error,
          output: audit_output,
          stats: stats,
          summary: format_audit_summary(stats),
          duration_ms: duration_ms
        }

      {{:error, unused_output}, {:error, audit_output}} ->
        combined_output =
          "=== Unused Dependencies ===\n#{unused_output}\n\n=== Security Audit ===\n#{audit_output}"

        unused_count = parse_unused_count(unused_output)
        audit_stats = parse_audit_output(audit_output)

        %{
          name: "Dependencies",
          status: :error,
          output: combined_output,
          stats: Map.put(audit_stats, :unused_deps, unused_count),
          summary: "Unused dependencies and security issues found",
          duration_ms: duration_ms
        }
    end
  end

  defp parse_unused_count(output) do
    # Parse output like "Unused dependencies in mix.lock: foo, bar, baz"
    # Extract count of unused dependencies
    case Regex.run(~r/Unused dependencies.*?:\s*(.+)/, output) do
      [_, deps_str] ->
        deps_str
        |> String.split(",")
        |> Enum.map(&String.trim/1)
        |> length()

      _ ->
        0
    end
  end

  defp parse_audit_output(output) do
    # Parse mix deps.audit output for vulnerability counts
    # Output format includes advisories with severity levels
    %{
      vulnerabilities: count_vulnerabilities(output),
      high_severity: count_by_severity(output, "high"),
      medium_severity: count_by_severity(output, "medium"),
      low_severity: count_by_severity(output, "low")
    }
  end

  defp count_vulnerabilities(output) do
    # Count total number of vulnerability advisories
    # Look for lines like "Advisory:" or "Package:" as markers
    output
    |> String.split("\n")
    |> Enum.count(&(String.contains?(&1, "Advisory:") or String.contains?(&1, "advisory")))
  end

  defp count_by_severity(output, severity) do
    # Count vulnerabilities by severity level
    # Look for lines like "Severity: high" or similar patterns
    output
    |> String.split("\n")
    |> Enum.count(&String.match?(&1, ~r/severity:?\s*#{severity}/i))
  end

  defp build_success_summary(audit_ran?) do
    if audit_ran? do
      "No unused dependencies or security issues"
    else
      "No unused dependencies"
    end
  end

  defp format_audit_summary(stats) do
    total = stats[:vulnerabilities] || 0
    high = stats[:high_severity] || 0

    cond do
      high > 0 -> "#{total} vulnerabilities (#{high} high severity)"
      total > 0 -> "#{total} vulnerabilities found"
      true -> "Security issues detected"
    end
  end
end
