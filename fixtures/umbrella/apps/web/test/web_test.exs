defmodule WebTest do
  use ExUnit.Case

  test "increment/1 works" do
    assert Web.increment(1) == 2
  end
end
