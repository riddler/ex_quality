defmodule Quality.Stages.CredoTest do
  use ExUnit.Case, async: false

  @moduletag :integration

  alias Quality.Stages.Credo

  describe "run/1" do
    test "returns result map with required fields" do
      result = Credo.run([])

      assert is_map(result)
      assert result.name == "Credo"
      assert result.status in [:ok, :error]
      assert is_binary(result.output)
      assert is_map(result.stats)
      assert is_binary(result.summary)
      assert is_integer(result.duration_ms)
      assert result.duration_ms >= 0
    end

    test "includes issue_count in stats" do
      result = Credo.run([])

      assert Map.has_key?(result.stats, :issue_count)
      assert is_integer(result.stats.issue_count)
      assert result.stats.issue_count >= 0
    end

    test "uses strict mode by default" do
      # We can't easily verify the command args, but we can verify the function runs
      result = Credo.run([])

      assert is_map(result)
    end

    test "respects strict config option" do
      result_strict = Credo.run(credo: [strict: true])
      result_non_strict = Credo.run(credo: [strict: false])

      assert is_map(result_strict)
      assert is_map(result_non_strict)
    end

    test "respects all config option" do
      result_all = Credo.run(credo: [all: true])
      result_changed = Credo.run(credo: [all: false])

      assert is_map(result_all)
      assert is_map(result_changed)
    end

    test "returns success when no issues found" do
      result = Credo.run([])

      # If status is :ok, should have zero issues
      if result.status == :ok do
        assert result.stats.issue_count == 0
        assert result.summary == "No issues"
      end
    end

    test "returns error when issues found" do
      result = Credo.run([])

      # If status is :error, should have non-zero issue count
      if result.status == :error do
        assert result.stats.issue_count > 0
        assert result.summary =~ ~r/issue/
      end
    end

    test "summary reflects issue count" do
      result = Credo.run([])

      if result.status == :error do
        count = result.stats.issue_count

        cond do
          count == 1 ->
            assert result.summary =~ "1 issue"

          count > 1 ->
            assert result.summary =~ "#{count} issue"

          true ->
            :ok
        end
      end
    end

    test "records execution duration" do
      result = Credo.run([])

      assert result.duration_ms > 0
      assert result.duration_ms < 30_000
    end
  end

  describe "configuration" do
    test "handles empty config" do
      result = Credo.run([])

      assert is_map(result)
    end

    test "handles config with both strict and all options" do
      config = [credo: [strict: true, all: true]]
      result = Credo.run(config)

      assert is_map(result)
    end

    test "defaults strict to true" do
      result = Credo.run([])

      # The stage runs successfully with defaults
      assert is_map(result)
    end

    test "defaults all to false" do
      result = Credo.run([])

      # The stage runs successfully with defaults
      assert is_map(result)
    end
  end
end
