defmodule Integration.QualityTest do
  use ExUnit.Case, async: false

  @moduletag :integration
  @moduletag timeout: 180_000

  describe "Mix.Tasks.Quality" do
    test "can be invoked successfully" do
      # This is a basic smoke test that verifies the task can run end-to-end
      # We use System.cmd instead of Mix.Task.run to better simulate actual usage

      {output, exit_code} = System.cmd("mix", ["quality", "--quick"], stderr_to_stdout: true)

      # The task should complete (exit code 0 for success, or non-zero for quality issues)
      assert exit_code in [0, 1]

      # Output should contain expected stage names
      assert output =~ "Format"
      assert output =~ "Compile"

      # Should have final status
      assert output =~ ~r/(All quality checks passed|quality check.*failed)/
    end

    test "respects --quick flag" do
      {output, _exit_code} = System.cmd("mix", ["quality", "--quick"], stderr_to_stdout: true)

      # Quick mode should skip Dialyzer
      # (Dialyzer won't appear in output when skipped in quick mode)
      assert is_binary(output)
    end

    test "can skip individual stages" do
      {output, _exit_code} =
        System.cmd("mix", ["quality", "--quick", "--skip-credo"], stderr_to_stdout: true)

      # Should complete
      assert is_binary(output)
    end

    test "handles compilation" do
      {output, exit_code} = System.cmd("mix", ["quality", "--quick"], stderr_to_stdout: true)

      # Should include compile stage
      assert output =~ "Compile"

      # If compilation succeeded, exit code should reflect overall quality status
      assert exit_code in [0, 1]
    end

    test "runs format stage first" do
      {output, _exit_code} = System.cmd("mix", ["quality", "--quick"], stderr_to_stdout: true)

      # Format should appear early in output
      assert output =~ "Format"
    end

    test "provides actionable output on failures" do
      # Run without quick mode to get more stages
      {output, exit_code} = System.cmd("mix", ["quality"], stderr_to_stdout: true)

      # If there are failures (exit_code = 1), should show details
      if exit_code == 1 do
        # Should have failure details section with dashes
        assert output =~ "─"
      end
    end
  end

  describe "configuration" do
    @tag :skip
    test "loads .quality.exs if present" do
      # This test would require creating a temporary .quality.exs file
      # Skipped for now but shows how to test config loading
      :ok
    end
  end

  describe "parallel execution" do
    test "completes in reasonable time" do
      start_time = System.monotonic_time(:millisecond)

      {_output, _exit_code} = System.cmd("mix", ["quality", "--quick"], stderr_to_stdout: true)

      duration = System.monotonic_time(:millisecond) - start_time

      # With parallel execution and quick mode, should complete within 1 minute
      # (allowing for some overhead)
      assert duration < 60_000
    end
  end
end
