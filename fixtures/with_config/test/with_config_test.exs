defmodule WithConfigTest do
  use ExUnit.Case

  test "add/2 works" do
    assert WithConfig.add(1, 2) == 3
  end
end
