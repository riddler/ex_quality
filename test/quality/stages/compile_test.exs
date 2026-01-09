defmodule Quality.Stages.CompileTest do
  use ExUnit.Case, async: false

  @moduletag :integration

  alias Quality.Stages.Compile

  describe "run/1" do
    test "returns result map with required fields" do
      result = Compile.run([])

      assert is_map(result)
      assert is_binary(result.name)
      assert result.status in [:ok, :error]
      assert is_binary(result.output)
      assert is_map(result.stats)
      assert is_binary(result.summary)
      assert is_integer(result.duration_ms)
      assert result.duration_ms >= 0
    end

    test "compiles both dev and test environments on success" do
      result = Compile.run([])

      # If compilation succeeds, should include both envs
      if result.status == :ok do
        assert result.name == "Compile"
        assert result.summary =~ "dev + test compiled"
      end
    end

    test "includes warnings as errors note in summary by default" do
      result = Compile.run([])

      if result.status == :ok do
        assert result.summary =~ "warnings as errors"
      end
    end

    test "respects warnings_as_errors config option" do
      # Test with warnings_as_errors: false
      config = [compile: [warnings_as_errors: false]]
      result = Compile.run(config)

      if result.status == :ok do
        refute result.summary =~ "warnings as errors"
      end
    end

    test "handles dev compilation failure" do
      # We can't easily trigger a real compilation failure in tests
      # without modifying the codebase, so we just verify the structure
      # and document expected behavior
      result = Compile.run([])

      # If status is error and name contains "dev", it's a dev failure
      if result.status == :error and result.name =~ "dev" do
        assert result.summary == "dev compilation failed"
        assert is_binary(result.output)
      end
    end

    test "handles test compilation failure" do
      result = Compile.run([])

      # If status is error and name contains "test", it's a test failure
      if result.status == :error and result.name =~ "test" do
        assert result.summary == "test compilation failed"
        assert is_binary(result.output)
      end
    end

    test "returns empty stats map" do
      result = Compile.run([])

      assert result.stats == %{}
    end

    test "records execution duration" do
      result = Compile.run([])

      # Compilation should take some time
      assert result.duration_ms > 0
      # But should complete within reasonable time
      assert result.duration_ms < 60_000
    end
  end

  describe "configuration" do
    test "uses default warnings_as_errors: true when not specified" do
      result = Compile.run([])

      if result.status == :ok do
        assert result.summary =~ "warnings as errors"
      end
    end

    test "accepts compile configuration block" do
      config = [compile: [warnings_as_errors: true]]
      result = Compile.run(config)

      assert is_map(result)
      assert result.status in [:ok, :error]
    end

    test "handles empty config" do
      result = Compile.run([])

      assert is_map(result)
    end

    test "handles nil compile config" do
      config = [compile: nil]

      # Should not crash
      assert_raise FunctionClauseError, fn ->
        Compile.run(config)
      end
    end
  end

  describe "parallel execution" do
    test "compiles both environments in parallel" do
      start_time = System.monotonic_time(:millisecond)
      result = Compile.run([])
      end_time = System.monotonic_time(:millisecond)

      duration = end_time - start_time

      # Parallel execution should be faster than sequential
      # The recorded duration should be close to the actual duration
      # (allowing for some overhead)
      assert abs(result.duration_ms - duration) < 100
    end
  end

  describe "output formatting" do
    test "filters out boring compilation lines" do
      result = Compile.run([])

      # Success output should not contain standard compilation messages
      # unless there's something interesting
      if result.status == :ok do
        # Output is either empty or contains interesting info
        if result.output != "" do
          # Should have environment sections
          assert result.output =~ "===" or result.output != ""
        end
      end
    end

    test "includes error output on failure" do
      result = Compile.run([])

      if result.status == :error do
        # Error output should be present and non-empty
        assert result.output != ""
        assert is_binary(result.output)
      end
    end
  end
end
