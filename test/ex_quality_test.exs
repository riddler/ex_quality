defmodule ExQualityTest do
  use ExUnit.Case
  doctest ExQuality

  test "returns version" do
    assert ExQuality.version() == to_string(Application.spec(:ex_quality, :vsn))
  end
end
