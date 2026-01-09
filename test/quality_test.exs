defmodule QualityTest do
  use ExUnit.Case
  doctest Quality

  test "greets the world" do
    assert Quality.hello() == :world
  end
end
