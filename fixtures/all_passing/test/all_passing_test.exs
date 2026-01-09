defmodule AllPassingTest do
  use ExUnit.Case

  test "add/2 works correctly" do
    assert AllPassing.add(1, 2) == 3
  end
end
