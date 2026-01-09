defmodule Quality.Stages.DialyzerTest do
  use ExUnit.Case, async: false

  @moduletag :integration

  alias Quality.Stages.Dialyzer

  @moduletag timeout: 120_000

  describe "run/1" do
    test "returns result map with required fields" do
      result = Dialyzer.run([])

      assert is_map(result)
      assert result.name == "Dialyzer"
      assert result.status in [:ok, :error]
      assert is_binary(result.output)
      assert is_map(result.stats)
      assert is_binary(result.summary)
      assert is_integer(result.duration_ms)
      assert result.duration_ms >= 0
    end

    test "includes warning_count in stats" do
      result = Dialyzer.run([])

      assert Map.has_key?(result.stats, :warning_count)
      assert is_integer(result.stats.warning_count)
      assert result.stats.warning_count >= 0
    end

    test "returns success when no warnings found" do
      result = Dialyzer.run([])

      # If status is :ok, should have zero warnings
      if result.status == :ok do
        assert result.stats.warning_count == 0
        # Summary should indicate success
        assert result.summary =~ ~r/(No warnings|some files skipped)/
      end
    end

    test "returns error when warnings found" do
      result = Dialyzer.run([])

      # If status is :error, should have warning details
      if result.status == :error do
        # Either has warnings or failed for another reason
        if result.stats.warning_count > 0 do
          assert result.summary =~ ~r/warning/
        else
          assert result.summary =~ ~r/(failed|error)/i
        end
      end
    end

    test "summary reflects warning count" do
      result = Dialyzer.run([])

      if result.status == :error and result.stats.warning_count > 0 do
        count = result.stats.warning_count

        case count do
          1 ->
            assert result.summary == "1 warning"

          n when n > 1 ->
            assert result.summary == "#{n} warnings"
        end
      end
    end

    test "handles debug_info errors gracefully" do
      result = Dialyzer.run([])

      # If there are debug_info errors but no actual warnings,
      # the stage should still pass
      if result.status == :ok and result.summary =~ "skipped" do
        assert result.stats.warning_count == 0
      end
    end

    test "records execution duration" do
      result = Dialyzer.run([])

      # Dialyzer can take a while, especially on first run
      assert result.duration_ms > 0
      # Allow up to 2 minutes
      assert result.duration_ms < 120_000
    end
  end

  describe "configuration" do
    test "handles empty config" do
      result = Dialyzer.run([])

      assert is_map(result)
    end

    test "ignores config parameter" do
      # Dialyzer stage doesn't use config
      result1 = Dialyzer.run([])
      result2 = Dialyzer.run(some_option: true)

      assert result1.name == result2.name
    end
  end

  describe "output parsing" do
    test "output contains execution details" do
      result = Dialyzer.run([])

      # Output should have some content
      assert is_binary(result.output)

      # If there are warnings, output should contain file paths
      if result.stats.warning_count > 0 do
        assert result.output =~ ~r/\.exs?/
      end
    end
  end
end
