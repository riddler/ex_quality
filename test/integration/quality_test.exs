defmodule Integration.QualityTest do
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
      # Config disables dialyzer, so it shouldn't appear
      refute output =~ "Dialyzer"
    end
  end

  describe "CLI options" do
    test "--quick flag skips dialyzer" do
      fixture_path = copy_fixture("all_passing")

      # Install deps
      {_output, 0} = System.cmd("mix", ["deps.get"], cd: fixture_path, stderr_to_stdout: true)

      {output, _exit_code} =
        System.cmd("mix", ["quality", "--quick"], cd: fixture_path, stderr_to_stdout: true)

      # Quick mode should skip Dialyzer
      refute output =~ "Dialyzer"
    end

    test "--skip-credo flag skips credo" do
      fixture_path = copy_fixture("credo_issues")

      # Install deps
      {_output, 0} = System.cmd("mix", ["deps.get"], cd: fixture_path, stderr_to_stdout: true)

      {output, _exit_code} =
        System.cmd("mix", ["quality", "--skip-credo"], cd: fixture_path, stderr_to_stdout: true)

      # Should not run Credo
      refute output =~ "Credo"
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
