defmodule ExQuality.Stages.Dependencies do
  @moduledoc """
  Checks dependency health by running:

  1. `mix deps.unlock --check-unused` - Detects dependencies in mix.lock
     that are no longer referenced in mix.exs
  2. `mix deps.audit --format json` - Scans dependencies for known security
     vulnerabilities using the mix_audit package

  Both checks run in parallel and results are combined.

  This stage always runs (unused dependency check). The security audit
  is automatically enabled only if `:mix_audit` is in deps.

  ## Findings

  Each vulnerability becomes a finding against the lockfile that holds the
  vulnerable version, naming the advisory, the version in use and the version
  that fixes it:

      mix.lock
        -  [error] plug 1.13.6: Arbitrary code execution (high severity, patched in 1.14.0) (GHSA-xxxx-yyyy-zzzz)

  The advisory is read from mix_audit's JSON report rather than counted out of
  its human output, where a substring search for `Advisory:` counted headings
  and one for `severity: high` counted whatever happened to say so.

  Unused dependencies become findings too, because a stage that rendered only
  half of what it found would hide the other half. Either half that does not
  parse turns findings off for the whole stage, so the tools' output is printed
  in full instead.
  """

  alias ExQuality.Aliases
  alias ExQuality.Finding
  alias ExQuality.Json
  alias ExQuality.Umbrella

  # Most severe first, so the summary leads with what to look at.
  @severity_order ~w(critical high moderate medium low)

  @doc """
  Runs the dependencies stage.

  ## Config options

  - `check_unused` - Check for unused dependencies (default: true)
  - `audit` - Run security audit if available (default: :auto)
  - `audit_available` - Whether mix_audit is available (set by auto-detection)
  """
  @spec run(keyword()) :: ExQuality.Stage.result()
  def run(config) do
    if Aliases.shadowing?("deps.unlock") do
      Aliases.shadowed("Dependencies", "deps.unlock")
    else
      check(config)
    end
  end

  defp check(config) do
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
      System.cmd("mix", ["deps.audit", "--format", "json"],
        env: [{"MIX_ENV", "dev"}],
        stderr_to_stdout: true
      )

    if exit_code == 0, do: {:ok, output}, else: {:error, output}
  end

  defp combine_results({:ok, _unused}, {:ok, _audit}, audit_ran?, duration_ms) do
    %{
      name: "Dependencies",
      status: :ok,
      output: "",
      stats: %{},
      summary: build_success_summary(audit_ran?),
      duration_ms: duration_ms
    }
  end

  defp combine_results(unused_result, audit_result, _audit_ran?, duration_ms) do
    unused = unused(unused_result)
    audit = audit(audit_result)

    %{
      name: "Dependencies",
      status: :error,
      output: output(unused_result, audit_result),
      findings: findings(unused, audit),
      stats: Map.merge(unused.stats, audit.stats),
      summary: summary(unused, audit),
      duration_ms: duration_ms
    }
  end

  # Findings stand in for the tools' output, so they are used only when every
  # failing check parsed into some. A half that parsed into nothing would
  # otherwise be dropped from a run that rendered the other half.
  defp findings(unused, audit) do
    if unused.parsed? and audit.parsed? do
      Finding.sort(unused.findings ++ audit.findings)
    else
      []
    end
  end

  defp output({:error, unused}, {:error, audit}) do
    "=== Unused Dependencies ===\n#{unused}\n\n=== Security Audit ===\n#{audit}"
  end

  defp output({:error, unused}, {:ok, _audit}), do: unused
  defp output({:ok, _unused}, {:error, audit}), do: audit

  defp unused({:ok, _output}), do: %{findings: [], stats: %{}, parsed?: true, failed?: false}

  defp unused({:error, output}) do
    packages = unused_packages(output)

    %{
      findings: Enum.map(packages, &unused_finding/1),
      stats: %{unused_deps: length(packages)},
      parsed?: packages != [],
      failed?: true
    }
  end

  # "Unused dependencies in mix.lock: foo, bar, baz"
  defp unused_packages(output) do
    case Regex.run(~r/Unused dependencies.*?:\s*(.+)/, output) do
      [_match, packages] ->
        packages |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))

      _no_match ->
        []
    end
  end

  defp unused_finding(package) do
    %Finding{
      file: lockfile(),
      severity: :error,
      check: "unused",
      message: "#{package} is in mix.lock but no longer declared in mix.exs",
      raw: package
    }
  end

  defp audit({:ok, _output}), do: %{findings: [], stats: %{}, parsed?: true, failed?: false}

  defp audit({:error, output}) do
    case Json.decode(output) do
      {:ok, %{"vulnerabilities" => vulnerabilities}} when is_list(vulnerabilities) ->
        parsed_audit(vulnerabilities)

      _no_report ->
        %{findings: [], stats: %{}, parsed?: false, failed?: true}
    end
  end

  defp parsed_audit(vulnerabilities) do
    apps = Umbrella.apps_paths()
    parsed = Enum.flat_map(vulnerabilities, &vulnerability(&1, apps))

    %{
      findings: Enum.map(parsed, &elem(&1, 0)),
      stats: %{
        vulnerabilities: length(parsed),
        vulnerabilities_by_severity: by_severity(parsed)
      },
      # A failing audit that reported no vulnerability is mix_audit saying
      # something about itself, and its output is the only account of it.
      parsed?: parsed != [],
      failed?: true
    }
  end

  # Vulnerabilities are carried as `{finding, severity}` pairs, because the
  # summary breaks down by advisory severity and `Finding.severity` has already
  # been spent saying that a vulnerability blocks the run.
  defp vulnerability(%{"advisory" => advisory} = entry, apps) when is_map(advisory) do
    dependency = Map.get(entry, "dependency", %{})
    # mix_audit reports the lockfile as an absolute path.
    file = Finding.relative_path(Map.get(dependency, "lockfile")) || lockfile()
    severity = advisory |> Map.get("severity") |> normalize_severity()

    finding = %Finding{
      file: file,
      app: Umbrella.app_for_path(file, apps),
      severity: :error,
      check: Map.get(advisory, "id"),
      message: message(dependency, advisory, severity),
      raw: Jason.encode!(entry)
    }

    [{finding, severity}]
  end

  defp vulnerability(_entry, _apps), do: []

  defp message(dependency, advisory, severity) do
    package = Map.get(dependency, "package", "(unknown)")
    version = Map.get(dependency, "version")
    title = advisory |> Map.get("title", "Known vulnerability") |> String.trim()

    "#{package}#{version_suffix(version)}: #{title} (#{severity} severity#{patch_note(advisory)})"
  end

  defp version_suffix(nil), do: ""
  defp version_suffix(version), do: " #{version}"

  defp patch_note(advisory) do
    case advisory |> Map.get("first_patched_versions") |> List.wrap() do
      [] -> ", no patched version"
      versions -> ", patched in #{Enum.join(versions, ", ")}"
    end
  end

  defp normalize_severity(severity) when is_binary(severity) and severity != "" do
    String.downcase(severity)
  end

  defp normalize_severity(_severity), do: "unknown"

  defp by_severity(parsed) do
    parsed
    |> Enum.frequencies_by(fn {_finding, severity} -> severity end)
    |> Enum.sort_by(fn {severity, _count} -> {severity_order(severity), severity} end)
  end

  defp severity_order(severity) do
    case Enum.find_index(@severity_order, &(&1 == severity)) do
      nil -> length(@severity_order)
      index -> index
    end
  end

  # The lockfile is where a vulnerable version is actually pinned, and it is
  # the file a reader changes to fix one.
  defp lockfile, do: "mix.lock"

  defp build_success_summary(true), do: "No unused dependencies or security issues"
  defp build_success_summary(false), do: "No unused dependencies"

  defp summary(%{failed?: true}, %{failed?: true}),
    do: "Unused dependencies and security issues found"

  defp summary(%{failed?: true}, _audit), do: "Unused dependencies detected"

  defp summary(_unused, %{stats: %{vulnerabilities: count}} = audit) when count > 0 do
    "#{count} vulnerabilit#{plural(count)}#{breakdown(audit.stats.vulnerabilities_by_severity)}"
  end

  defp summary(_unused, _audit), do: "Security issues detected"

  defp plural(1), do: "y"
  defp plural(_count), do: "ies"

  defp breakdown([]), do: ""

  defp breakdown(counts) do
    " (" <> Enum.map_join(counts, ", ", fn {severity, count} -> "#{count} #{severity}" end) <> ")"
  end
end
