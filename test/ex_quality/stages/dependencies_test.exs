defmodule ExQuality.Stages.DependenciesTest do
  use ExUnit.Case, async: true
  use Mimic

  alias ExQuality.Stages.Dependencies

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
      config = [dependencies: [audit_available: false]]
      result = Dependencies.run(config)

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

        "mix", ["deps.audit"], _opts ->
          output = """
          No vulnerabilities found.
          """

          {output, 0}
      end)

      :ok
    end

    test "returns success with audit" do
      config = [dependencies: [audit_available: true]]
      result = Dependencies.run(config)

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

        "mix", ["deps.audit"], _opts ->
          {"No vulnerabilities found", 0}
      end)

      :ok
    end

    test "returns error with unused count" do
      config = [dependencies: [audit_available: true]]
      result = Dependencies.run(config)

      assert result.status == :error
      assert result.summary == "Unused dependencies detected"
      assert result.stats.unused_deps == 2
      assert result.output =~ "some_old_package"
      assert result.output =~ "another_unused_lib"
    end
  end

  describe "run/1 - security issues found" do
    setup do
      # Mock both commands using stub (since they run in parallel, order is non-deterministic)
      System
      |> stub(:cmd, fn
        "mix", ["deps.unlock", "--check-unused"], _opts ->
          {"All dependencies in mix.lock are being used", 0}

        "mix", ["deps.audit"], _opts ->
          output = """
          Advisory: GHSA-xxxx-yyyy-zzzz
          Package: plug
          Severity: high
          Description: Arbitrary code execution via malformed request
          Affected versions: < 1.14.0
          Patched versions: >= 1.14.0

          Advisory: GHSA-aaaa-bbbb-cccc
          Package: phoenix
          Severity: medium
          Description: Cross-site scripting in error pages
          Affected versions: < 1.7.2
          Patched versions: >= 1.7.2

          2 vulnerabilities found.
          """

          {output, 1}
      end)

      :ok
    end

    test "returns error with vulnerability count" do
      config = [dependencies: [audit_available: true]]
      result = Dependencies.run(config)

      assert result.status == :error
      assert result.stats.vulnerabilities == 2
      assert result.stats.high_severity == 1
      assert result.summary =~ "2 vulnerabilities (1 high severity)"
      assert result.output =~ "plug"
      assert result.output =~ "phoenix"
    end
  end

  describe "run/1 - both unused deps and security issues" do
    setup do
      # Mock both commands using stub (since they run in parallel)
      System
      |> stub(:cmd, fn
        "mix", ["deps.unlock", "--check-unused"], _opts ->
          {"Unused dependencies in mix.lock: old_pkg", 1}

        "mix", ["deps.audit"], _opts ->
          output = """
          Advisory: GHSA-xxxx-yyyy-zzzz
          Package: plug
          Severity: high
          1 vulnerability found.
          """

          {output, 1}
      end)

      :ok
    end

    test "returns error with combined summary" do
      config = [dependencies: [audit_available: true]]
      result = Dependencies.run(config)

      assert result.status == :error
      assert result.summary == "Unused dependencies and security issues found"
      assert result.stats.unused_deps == 1
      assert result.stats.vulnerabilities == 1
      assert result.output =~ "=== Unused Dependencies ==="
      assert result.output =~ "=== Security Audit ==="
    end
  end

  describe "run/1 - timing" do
    setup do
      System
      |> stub(:cmd, fn _cmd, _args, _opts ->
        Process.sleep(10)
        {"No issues", 0}
      end)

      :ok
    end

    test "records execution duration" do
      config = [dependencies: [audit_available: true]]
      result = Dependencies.run(config)

      # Both checks run in parallel, so duration should be ~10ms (not 20ms)
      assert result.duration_ms >= 10
      assert result.duration_ms < 30
    end
  end
end
