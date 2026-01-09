defmodule Quality.Stages.GettextTest do
  use ExUnit.Case, async: false

  @moduletag :integration

  alias Quality.Stages.Gettext

  describe "run/1" do
    test "returns result map with required fields" do
      result = Gettext.run([])

      assert is_map(result)
      assert result.name == "Gettext"
      assert result.status in [:ok, :error]
      assert is_binary(result.output)
      assert is_map(result.stats)
      assert is_binary(result.summary)
      assert is_integer(result.duration_ms)
      assert result.duration_ms >= 0
    end

    test "handles projects without gettext" do
      # If the project doesn't have gettext files, should handle gracefully
      result = Gettext.run([])

      assert is_map(result)
    end

    test "handles empty config" do
      result = Gettext.run([])

      assert is_map(result)
    end

    test "records execution duration" do
      result = Gettext.run([])

      assert result.duration_ms >= 0
      assert result.duration_ms < 30_000
    end
  end
end
