defmodule ExQuality.StageTest do
  use ExUnit.Case, async: true

  alias ExQuality.Stage

  doctest ExQuality.Stage

  describe "findings/1" do
    test "returns the findings a stage reported" do
      finding = %ExQuality.Finding{file: "lib/user.ex", line: 1, message: "boom"}

      assert Stage.findings(%{findings: [finding]}) == [finding]
    end

    test "returns an empty list when the stage reported none" do
      assert Stage.findings(%{name: "Credo"}) == []
    end
  end

  describe "skipped/2" do
    test "carries the reason in the summary" do
      result = Stage.skipped("Doctor", ":doctor not installed")

      assert result.status == :skipped
      assert result.name == "Doctor"
      assert result.summary == ":doctor not installed"
    end

    test "has nothing to report beyond the reason" do
      result = Stage.skipped("Doctor", ":doctor not installed")

      assert result.output == ""
      assert result.stats == %{}
      assert result.duration_ms == 0
      assert Stage.findings(result) == []
    end
  end
end
