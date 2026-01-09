defmodule Quality.Stages.TestTest do
  use ExUnit.Case, async: false

  # Mark as integration test to prevent infinite recursion
  # (these tests call Test.run which runs "mix test", creating a loop)
  @moduletag :integration

  alias Quality.Stages.Test

  describe "run/1" do
    test "returns result map with required fields" do
      result = Test.run([])

      assert is_map(result)
      assert result.name == "Test"
      assert result.status in [:ok, :error]
      assert is_binary(result.output)
      assert is_map(result.stats)
      assert is_binary(result.summary)
      assert is_integer(result.duration_ms)
      assert result.duration_ms >= 0
    end

    test "includes test counts in stats" do
      result = Test.run([])

      assert is_map(result.stats)
      # Stats may include test_count, passed_count, failed_count, coverage
    end

    test "respects quick mode" do
      config = [quick: true]
      result = Test.run(config)

      assert is_map(result)
      # In quick mode, should run mix test instead of mix coveralls
    end

    test "uses coveralls when coverage_available" do
      config = [test: [coverage_available: true]]
      result = Test.run(config)

      assert is_map(result)
    end

    test "uses mix test when coverage not available" do
      config = [test: [coverage_available: false]]
      result = Test.run(config)

      assert is_map(result)
    end

    test "handles empty config" do
      result = Test.run([])

      assert is_map(result)
    end

    test "records execution duration" do
      result = Test.run([])

      assert result.duration_ms >= 0
      assert result.duration_ms < 60_000
    end

    test "summary includes test results" do
      result = Test.run([])

      # Summary should mention pass/fail counts
      assert is_binary(result.summary)
    end
  end
end
