defmodule TestFailuresTest do
  use ExUnit.Case

  test "add/2 works" do
    assert TestFailures.add(1, 2) == 3
  end

  test "this test will fail" do
    assert TestFailures.add(2, 2) == 5
  end

  test "multiply will also fail" do
    assert TestFailures.multiply(3, 3) == 10
  end
end
