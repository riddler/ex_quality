defmodule Quality.Stages.DoctorTest do
  use ExUnit.Case, async: false

  @moduletag :integration

  alias Quality.Stages.Doctor

  describe "run/1" do
    test "returns result map with required fields" do
      result = Doctor.run([])

      assert is_map(result)
      assert result.name == "Doctor"
      assert result.status in [:ok, :error, :skipped]
      assert is_binary(result.output)
      assert is_map(result.stats)
      assert is_binary(result.summary)
      assert is_integer(result.duration_ms)
      assert result.duration_ms >= 0
    end

    test "respects summary_only config option" do
      config = [doctor: [summary_only: true]]
      result = Doctor.run(config)

      assert is_map(result)
    end

    test "handles empty config" do
      result = Doctor.run([])

      assert is_map(result)
    end

    test "records execution duration" do
      result = Doctor.run([])

      assert result.duration_ms >= 0
      assert result.duration_ms < 30_000
    end
  end
end
