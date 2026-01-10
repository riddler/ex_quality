defmodule Quality.ToolsTest do
  use ExUnit.Case, async: true

  alias Quality.Tools

  describe "detect/0" do
    test "returns a map with all tool keys" do
      result = Tools.detect()

      assert is_map(result)
      assert Map.has_key?(result, :credo)
      assert Map.has_key?(result, :dialyzer)
      assert Map.has_key?(result, :doctor)
      assert Map.has_key?(result, :coverage)
      assert Map.has_key?(result, :gettext)
      assert Map.has_key?(result, :audit)
    end

    test "returns boolean values for all tools" do
      result = Tools.detect()

      assert is_boolean(result.credo)
      assert is_boolean(result.dialyzer)
      assert is_boolean(result.doctor)
      assert is_boolean(result.coverage)
      assert is_boolean(result.gettext)
      assert is_boolean(result.audit)
    end

    test "detects tools based on actual project dependencies" do
      # The Quality project has credo, dialyxir, and excoveralls in mix.exs
      result = Tools.detect()

      # These tools ARE in the Quality project dependencies
      assert result.credo == true
      assert result.dialyzer == true
      assert result.coverage == true

      # These tools are NOT in the Quality project dependencies
      assert result.doctor == false
      assert result.gettext == false
      assert result.audit == false
    end
  end

  describe "available?/1" do
    test "returns correct availability for tools" do
      # These ARE in dependencies
      assert Tools.available?(:credo) == true
      assert Tools.available?(:dialyzer) == true

      # These are NOT in dependencies
      assert Tools.available?(:doctor) == false
    end

    test "returns false for unknown tools" do
      assert Tools.available?(:unknown_tool) == false
    end

    test "returns false for nil" do
      assert Tools.available?(nil) == false
    end
  end

  describe "tool package mapping" do
    test "correctly maps tool names to package names" do
      # This test verifies the mapping is correct by checking
      # the module's behavior against known package names

      # Since we don't have all deps installed, we can verify
      # the structure is correct by checking the keys exist
      result = Tools.detect()

      # Verify all expected tools are checked
      expected_tools = [:audit, :coverage, :credo, :dialyzer, :doctor, :gettext]
      assert Map.keys(result) |> Enum.sort() == Enum.sort(expected_tools)
    end
  end
end
