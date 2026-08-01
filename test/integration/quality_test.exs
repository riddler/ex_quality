defmodule Integration.ExQualityTest do
  use ExUnit.Case, async: false

  @moduletag :integration
  @moduletag timeout: 180_000

  @fixtures_dir Path.expand("../../fixtures", __DIR__)
  @tmp_dir Path.expand("../../fixtures/tmp", __DIR__)

  setup do
    # Ensure tmp directory exists and is clean
    File.rm_rf!(@tmp_dir)
    File.mkdir_p!(@tmp_dir)

    on_exit(fn ->
      File.rm_rf!(@tmp_dir)
    end)

    :ok
  end

  describe "all_passing fixture" do
    test "passes all quality checks" do
      fixture_path = copy_fixture("all_passing")

      # Install deps first
      {_output, 0} = System.cmd("mix", ["deps.get"], cd: fixture_path, stderr_to_stdout: true)

      {output, exit_code} = run_quality(fixture_path)

      assert exit_code == 0, "Expected success but got exit code #{exit_code}. Output:\n#{output}"
      assert output =~ "All quality checks passed"
      assert output =~ "Format"
      assert output =~ "Compile"
      assert output =~ "Test"
    end
  end

  describe "format_needed fixture" do
    test "auto-fixes formatting and passes" do
      fixture_path = copy_fixture("format_needed")

      # Install deps
      {_output, 0} = System.cmd("mix", ["deps.get"], cd: fixture_path, stderr_to_stdout: true)

      {output, exit_code} = run_quality(fixture_path)

      assert exit_code == 0, "Expected success after format. Output:\n#{output}"
      assert output =~ ~r/Format.*Formatted \d+ file/
    end
  end

  describe "credo_issues fixture" do
    test "fails with credo violations" do
      fixture_path = copy_fixture("credo_issues")

      # Install deps
      {_output, 0} = System.cmd("mix", ["deps.get"], cd: fixture_path, stderr_to_stdout: true)

      {output, exit_code} = run_quality(fixture_path)

      assert exit_code == 1, "Expected failure but got exit code #{exit_code}. Output:\n#{output}"
      assert output =~ "Credo - FAILED"
      assert output =~ "lib/credo_issues.ex"
    end

    test "writes a report a caller can route on" do
      fixture_path = copy_fixture("credo_issues")

      {_output, 0} = System.cmd("mix", ["deps.get"], cd: fixture_path, stderr_to_stdout: true)

      {output, exit_code} = run_quality(fixture_path, ["--report", ".quality.json"])

      assert exit_code == 1, "Expected failure but got exit code #{exit_code}. Output:\n#{output}"

      report =
        fixture_path
        |> Path.join(".quality.json")
        |> File.read!()
        |> Jason.decode!()

      assert report["status"] == "error"

      credo = Enum.find(report["stages"], &(&1["name"] == "Credo"))

      assert credo["status"] == "error"
      assert Enum.any?(credo["findings"], &(&1["file"] == "lib/credo_issues.ex"))
    end
  end

  describe "compile_error fixture" do
    test "fails at compile stage" do
      fixture_path = copy_fixture("compile_error")

      # Install deps
      {_output, 0} = System.cmd("mix", ["deps.get"], cd: fixture_path, stderr_to_stdout: true)

      {output, exit_code} = run_quality(fixture_path)

      assert exit_code == 1, "Expected compilation failure. Output:\n#{output}"
      assert output =~ ~r/(Compile.*failed|Compilation failed)/
      assert output =~ "undefined_function"
    end
  end

  describe "test_failures fixture" do
    test "fails with test failures" do
      fixture_path = copy_fixture("test_failures")

      # Install deps
      {_output, 0} = System.cmd("mix", ["deps.get"], cd: fixture_path, stderr_to_stdout: true)

      {output, exit_code} = run_quality(fixture_path)

      assert exit_code == 1, "Expected test failure. Output:\n#{output}"
      assert output =~ "Test"
      assert output =~ ~r/(failed|FAILED)/
    end
  end

  describe "with_config fixture" do
    test "respects .quality.exs configuration" do
      fixture_path = copy_fixture("with_config")

      # Install deps
      {_output, 0} = System.cmd("mix", ["deps.get"], cd: fixture_path, stderr_to_stdout: true)

      {output, exit_code} = run_quality(fixture_path)

      assert exit_code == 0, "Expected success. Output:\n#{output}"
      # Config disables dialyzer, so it should say so rather than run
      assert output =~ "Dialyzer: skipped (disabled in .quality.exs)"
      refute output =~ "✓ Dialyzer"
    end

    test "runs the project's own stages and reports what they said" do
      fixture_path = copy_fixture("with_config")

      {_output, 0} = System.cmd("mix", ["deps.get"], cd: fixture_path, stderr_to_stdout: true)

      {output, exit_code} = run_quality(fixture_path)

      assert exit_code == 0, "Expected success. Output:\n#{output}"

      # The command printed the finding contract, so its own summary is used.
      assert output =~ "✓ House rules: No bare Logger calls"

      # A prerequisite the run cannot know about is not a code problem.
      assert output =~ "○ Prerequisite: skipped (nothing to check here)"
    end

    test "--skip reaches a custom stage, which has no --skip-<key> of its own" do
      fixture_path = copy_fixture("with_config")

      {_output, 0} = System.cmd("mix", ["deps.get"], cd: fixture_path, stderr_to_stdout: true)

      {output, exit_code} = run_quality(fixture_path, ["--skip", "house_rules"])

      assert exit_code == 0, "Expected success. Output:\n#{output}"
      assert output =~ "○ House rules: skipped (--skip house_rules)"
      refute output =~ "✓ House rules"
    end
  end

  describe "umbrella fixture" do
    test "detects a child app's tools and groups findings by app" do
      fixture_path = copy_fixture("umbrella")

      # Install deps
      {_output, 0} = System.cmd("mix", ["deps.get"], cd: fixture_path, stderr_to_stdout: true)

      {output, exit_code} = run_quality(fixture_path)

      # Credo is declared by apps/core only. Reading the umbrella root alone
      # would report it as not installed and pass the run.
      assert exit_code == 1, "Expected credo to run and fail. Output:\n#{output}"
      refute output =~ "Credo: skipped"
      assert output =~ "Credo - FAILED"
      assert output =~ "── core ──"
      assert output =~ "apps/core/lib/core.ex"

      # Both apps' suites are counted, not just the first one's.
      assert output =~ "Tests: 2 of 2 passed"
    end
  end

  describe "native_coverage fixture" do
    test "measures coverage without excoveralls and names the modules under the line" do
      fixture_path = copy_fixture("native_coverage")

      # Install deps
      {_output, 0} = System.cmd("mix", ["deps.get"], cd: fixture_path, stderr_to_stdout: true)

      {output, exit_code} = run_quality(fixture_path)

      # The project has no excoveralls, only a test_coverage threshold, so the
      # coverage gate has to come from `mix test --cover`.
      assert exit_code == 1, "Expected the coverage threshold to fail. Output:\n#{output}"
      assert output =~ ~r/Tests: Coverage \d+\.\d+% \(required: 90\.0%\)/
      assert output =~ "lib/native_coverage.ex"
      assert output =~ ~r/NativeCoverage is \d+\.\d+% covered \(threshold 90\.0%\)/
    end

    test "--quick runs the suite without enforcing the threshold" do
      fixture_path = copy_fixture("native_coverage")

      # Install deps
      {_output, 0} = System.cmd("mix", ["deps.get"], cd: fixture_path, stderr_to_stdout: true)

      {output, exit_code} =
        System.cmd("mix", ["quality", "--quick"], cd: fixture_path, stderr_to_stdout: true)

      assert exit_code == 0, "Expected quick mode to pass. Output:\n#{output}"
      assert output =~ "Tests: 1 of 1 passed"
      refute output =~ "% coverage"
    end
  end

  describe "CLI options" do
    test "--quick flag skips dialyzer" do
      fixture_path = copy_fixture("all_passing")

      # Install deps
      {_output, 0} = System.cmd("mix", ["deps.get"], cd: fixture_path, stderr_to_stdout: true)

      {output, _exit_code} =
        System.cmd("mix", ["quality", "--quick"], cd: fixture_path, stderr_to_stdout: true)

      # Quick mode should skip Dialyzer, and say that it did. This fixture has
      # no dialyxir either, and the missing package is the reason reported when
      # both apply, so only the skip itself is asserted here.
      assert output =~ "○ Dialyzer: skipped ("
      refute output =~ "✓ Dialyzer"
    end

    test "--skip-credo flag skips credo" do
      fixture_path = copy_fixture("credo_issues")

      # Install deps
      {_output, 0} = System.cmd("mix", ["deps.get"], cd: fixture_path, stderr_to_stdout: true)

      {output, _exit_code} =
        System.cmd("mix", ["quality", "--skip-credo"], cd: fixture_path, stderr_to_stdout: true)

      # Should not run Credo, but should report that it was skipped
      assert output =~ "Credo: skipped (--skip-credo)"
      refute output =~ "✓ Credo"
      refute output =~ "Credo - FAILED"
    end
  end

  describe "parallel execution" do
    test "completes in reasonable time with --quick" do
      fixture_path = copy_fixture("all_passing")

      # Install deps
      {_output, 0} = System.cmd("mix", ["deps.get"], cd: fixture_path, stderr_to_stdout: true)

      start_time = System.monotonic_time(:millisecond)
      {_output, _exit_code} = run_quality(fixture_path, ["--quick"])
      duration = System.monotonic_time(:millisecond) - start_time

      # Should complete within 30 seconds for a minimal project
      assert duration < 30_000
    end
  end

  # Helper functions

  defp copy_fixture(fixture_name) do
    source = Path.join(@fixtures_dir, fixture_name)
    dest = Path.join(@tmp_dir, fixture_name)

    File.cp_r!(source, dest)
    dest
  end

  defp run_quality(fixture_path, args \\ []) do
    System.cmd("mix", ["quality" | args], cd: fixture_path, stderr_to_stdout: true)
  end
end
