defmodule ExQualityTest do
  use ExUnit.Case
  doctest ExQuality

  test "returns version" do
    assert ExQuality.version() == "0.1.0"
  end
end
