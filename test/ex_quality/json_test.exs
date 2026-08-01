defmodule ExQuality.JsonTest do
  use ExUnit.Case, async: true

  doctest ExQuality.Json

  alias ExQuality.Json

  describe "decode/1" do
    test "reads a document that is the whole output" do
      assert Json.decode(~s({"pass": true})) == {:ok, %{"pass" => true}}
    end

    test "reads a compact document printed after other output" do
      output = """
      Compiling 3 files (.ex)
      {"vulnerabilities":[],"pass":true}
      """

      assert {:ok, %{"pass" => true}} = Json.decode(output)
    end

    test "reads a pretty-printed document printed after other output" do
      output = "warning: variable is unused\n" <> Jason.encode!(%{issues: []}, pretty: true)

      assert Json.decode(output) == {:ok, %{"issues" => []}}
    end

    test "returns :error when the output holds no document" do
      assert Json.decode("** (Mix) The task \"credo\" could not be found") == :error
    end

    test "returns :error for empty output" do
      assert Json.decode("") == :error
    end

    test "does not mistake a nested object for the document" do
      output = "noise\n" <> Jason.encode!(%{issues: [%{check: "A"}]}, pretty: true)

      assert {:ok, %{"issues" => [%{"check" => "A"}]}} = Json.decode(output)
    end
  end
end
