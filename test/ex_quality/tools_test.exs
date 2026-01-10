defmodule ExQuality.ToolsTest do
  use ExUnit.Case, async: true

  alias ExQuality.Tools

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
      # The ExQuality project has credo, dialyxir, excoveralls, doctor, and mix_audit in mix.exs
      result = Tools.detect()

      # These tools ARE in the ExQuality project dependencies
      assert result.credo == true
      assert result.dialyzer == true
      assert result.coverage == true
      assert result.doctor == true
      assert result.audit == true

      # This tool is NOT in the ExQuality project dependencies
      assert result.gettext == false
    end
  end

  describe "available?/1" do
    test "returns correct availability for tools" do
      # These ARE in dependencies
      assert Tools.available?(:credo) == true
      assert Tools.available?(:dialyzer) == true
      assert Tools.available?(:doctor) == true

      # These are NOT in dependencies
      assert Tools.available?(:gettext) == false
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
