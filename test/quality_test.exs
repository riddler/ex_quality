defmodule QualityTest do
  use ExUnit.Case
  doctest Quality

  test "returns version" do
    assert Quality.version() == "0.1.0"
  end
end
