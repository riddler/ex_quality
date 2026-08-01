defmodule ExQuality.Stages.DependenciesTest do
  use ExUnit.Case, async: true
  use Mimic

  alias ExQuality.Stage
  alias ExQuality.Stages.Dependencies

  @audit_args ["deps.audit", "--format", "json"]
  @config [dependencies: [audit_available: true]]

  defp report(vulnerabilities) do
    Jason.encode!(%{"vulnerabilities" => vulnerabilities, "pass" => vulnerabilities == []})
  end

  defp vulnerability(attrs) do
    %{
      "dependency" => %{
        "package" => "plug",
        "version" => "1.13.6",
        "lockfile" => "mix.lock"
      },
      "advisory" => %{
        "id" => "GHSA-xxxx-yyyy-zzzz",
        "package" => "plug",
        "title" => "Arbitrary code execution via malformed request",
        "severity" => "high",
        "first_patched_versions" => ["1.14.0"],
        "url" => "https://github.com/advisories/GHSA-xxxx-yyyy-zzzz"
      }
    }
    |> Map.merge(attrs)
  end

  describe "run/1 - no issues (audit not available)" do
    setup do
      # Mock unused deps check - no unused
      System
      |> expect(:cmd, fn "mix", ["deps.unlock", "--check-unused"], _opts ->
        {"All dependencies in mix.lock are being used", 0}
      end)

      :ok
    end

    test "returns success without audit" do
      result = Dependencies.run(dependencies: [audit_available: false])

      assert result.name == "Dependencies"
      assert result.status == :ok
      assert result.summary == "No unused dependencies"
      assert is_integer(result.duration_ms)
      assert result.duration_ms >= 0
    end
  end

  describe "run/1 - no issues (audit available)" do
    setup do
      # Mock both commands using stub (since they run in parallel)
      System
      |> stub(:cmd, fn
        "mix", ["deps.unlock", "--check-unused"], _opts ->
          {"All dependencies in mix.lock are being used", 0}

        "mix", @audit_args, _opts ->
          {report([]), 0}
      end)

      :ok
    end

    test "returns success with audit" do
      result = Dependencies.run(@config)

      assert result.status == :ok
      assert result.summary == "No unused dependencies or security issues"
    end
  end

  describe "run/1 - unused dependencies found" do
    setup do
      # Mock both commands using stub (since they run in parallel)
      System
      |> stub(:cmd, fn
        "mix", ["deps.unlock", "--check-unused"], _opts ->
          output = """
          Unused dependencies in mix.lock: some_old_package, another_unused_lib

          Run `mix deps.unlock some_old_package another_unused_lib` to remove them.
          """

          {output, 1}

        "mix", @audit_args, _opts ->
          {report([]), 0}
      end)

      :ok
    end

    test "returns error with unused count" do
      result = Dependencies.run(@config)

      assert result.status == :error
      assert result.summary == "Unused dependencies detected"
      assert result.stats.unused_deps == 2
      assert result.output =~ "some_old_package"
      assert result.output =~ "another_unused_lib"
    end

    test "reports each unused dependency as a finding against the lockfile" do
      assert [some, another] = Stage.findings(Dependencies.run(@config))

      assert %ExQuality.Finding{file: "mix.lock", severity: :error, check: "unused"} = some
      assert some.message == "some_old_package is in mix.lock but no longer declared in mix.exs"
      assert another.message =~ "another_unused_lib"
    end

    test "keeps the output when the package list does not parse" do
      System
      |> stub(:cmd, fn
        "mix", ["deps.unlock", "--check-unused"], _opts -> {"Something else went wrong\n", 1}
        "mix", @audit_args, _opts -> {report([]), 0}
      end)

      result = Dependencies.run(@config)

      assert Stage.findings(result) == []
      assert result.output =~ "Something else went wrong"
    end
  end

  describe "run/1 - security issues found" do
    setup do
      vulnerabilities = [
        vulnerability(%{}),
        vulnerability(%{
          "dependency" => %{
            "package" => "phoenix",
            "version" => "1.7.1",
            "lockfile" => "mix.lock"
          },
          "advisory" => %{
            "id" => "GHSA-aaaa-bbbb-cccc",
            "title" => "Cross-site scripting in error pages",
            "severity" => "moderate",
            "first_patched_versions" => ["1.7.2"]
          }
        })
      ]

      System
      |> stub(:cmd, fn
        "mix", ["deps.unlock", "--check-unused"], _opts ->
          {"All dependencies in mix.lock are being used", 0}

        "mix", @audit_args, _opts ->
          {report(vulnerabilities), 1}
      end)

      :ok
    end

    test "returns error with vulnerability count and severities" do
      result = Dependencies.run(@config)

      assert result.status == :error
      assert result.stats.vulnerabilities == 2
      assert result.stats.vulnerabilities_by_severity == [{"high", 1}, {"moderate", 1}]
      assert result.summary == "2 vulnerabilities (1 high, 1 moderate)"
    end

    test "reports each vulnerability as a finding naming the advisory and the fix" do
      assert [plug, phoenix] = Stage.findings(Dependencies.run(@config))

      assert %ExQuality.Finding{
               file: "mix.lock",
               severity: :error,
               check: "GHSA-xxxx-yyyy-zzzz"
             } = plug

      assert plug.message ==
               "plug 1.13.6: Arbitrary code execution via malformed request " <>
                 "(high severity, patched in 1.14.0)"

      assert phoenix.check == "GHSA-aaaa-bbbb-cccc"
      assert phoenix.message =~ "phoenix 1.7.1"
      assert phoenix.message =~ "moderate severity, patched in 1.7.2"
    end

    test "keeps the vulnerability each finding came from" do
      [plug, _phoenix] = Stage.findings(Dependencies.run(@config))

      assert plug.raw =~ "GHSA-xxxx-yyyy-zzzz"
      assert plug.raw =~ "1.13.6"
    end
  end

  describe "run/1 - lockfile paths" do
    setup do
      # mix_audit reports the lockfile as an absolute path, which would
      # otherwise render as /Users/someone/code/app/mix.lock in the output and
      # differ between a laptop and CI for the same vulnerability.
      vulnerability =
        vulnerability(%{
          "dependency" => %{
            "package" => "plug",
            "version" => "1.13.6",
            "lockfile" => Path.join(File.cwd!(), "mix.lock")
          }
        })

      System
      |> stub(:cmd, fn
        "mix", ["deps.unlock", "--check-unused"], _opts -> {"", 0}
        "mix", @audit_args, _opts -> {report([vulnerability]), 1}
      end)

      :ok
    end

    test "reports an absolute lockfile relative to the project root" do
      assert [finding] = Stage.findings(Dependencies.run(@config))

      assert finding.file == "mix.lock"
    end
  end

  describe "run/1 - advisories without a severity or a patch" do
    setup do
      vulnerability =
        vulnerability(%{
          "advisory" => %{
            "id" => "GHSA-dddd-eeee-ffff",
            "title" => "Denial of service",
            "severity" => nil,
            "first_patched_versions" => []
          }
        })

      System
      |> stub(:cmd, fn
        "mix", ["deps.unlock", "--check-unused"], _opts -> {"", 0}
        "mix", @audit_args, _opts -> {report([vulnerability]), 1}
      end)

      :ok
    end

    test "says so rather than leaving the reader to guess" do
      result = Dependencies.run(@config)

      assert [finding] = Stage.findings(result)
      assert finding.message =~ "(unknown severity, no patched version)"
      assert result.summary == "1 vulnerability (1 unknown)"
    end
  end

  describe "run/1 - audit output that is not a report" do
    setup do
      System
      |> stub(:cmd, fn
        "mix", ["deps.unlock", "--check-unused"], _opts -> {"", 0}
        "mix", @audit_args, _opts -> {"** (Mix) Could not fetch the advisory database\n", 1}
      end)

      :ok
    end

    test "fails with the tool's own output rather than a silent pass" do
      result = Dependencies.run(@config)

      assert result.status == :error
      assert result.summary == "Security issues detected"
      assert Stage.findings(result) == []
      assert result.output =~ "Could not fetch the advisory database"
    end
  end

  describe "run/1 - both unused deps and security issues" do
    setup do
      System
      |> stub(:cmd, fn
        "mix", ["deps.unlock", "--check-unused"], _opts ->
          {"Unused dependencies in mix.lock: old_pkg", 1}

        "mix", @audit_args, _opts ->
          {report([vulnerability(%{})]), 1}
      end)

      :ok
    end

    test "returns error with combined summary" do
      result = Dependencies.run(@config)

      assert result.status == :error
      assert result.summary == "Unused dependencies and security issues found"
      assert result.stats.unused_deps == 1
      assert result.stats.vulnerabilities == 1
      assert result.output =~ "=== Unused Dependencies ==="
      assert result.output =~ "=== Security Audit ==="
    end

    test "renders findings from both halves, so neither is hidden" do
      assert [unused, vulnerability] = Stage.findings(Dependencies.run(@config))

      assert unused.check == "unused"
      assert vulnerability.check == "GHSA-xxxx-yyyy-zzzz"
    end

    test "falls back to output when one half does not parse" do
      System
      |> stub(:cmd, fn
        "mix", ["deps.unlock", "--check-unused"], _opts -> {"Unused dependencies!\n", 1}
        "mix", @audit_args, _opts -> {report([vulnerability(%{})]), 1}
      end)

      result = Dependencies.run(@config)

      assert Stage.findings(result) == []
      assert result.output =~ "Unused dependencies!"
      assert result.output =~ "GHSA-xxxx-yyyy-zzzz"
    end
  end

  describe "run/1 - timing" do
    setup do
      System
      |> stub(:cmd, fn _cmd, _args, _opts ->
        Process.sleep(10)
        {report([]), 0}
      end)

      :ok
    end

    test "records execution duration" do
      result = Dependencies.run(@config)

      # Both checks run in parallel, so duration should be ~10ms (not 20ms)
      assert result.duration_ms >= 10
      assert result.duration_ms < 30
    end
  end
end
