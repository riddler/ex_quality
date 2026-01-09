defmodule Quality.Stages.DoctorTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Quality.Stages.Doctor

  describe "run/1 - passing documentation" do
    setup do
      System
      |> expect(:cmd, fn "mix", ["doctor", "--raise"], _opts ->
        output = """
        Doctor file found. Loading configuration.

        ---------------------------------------------------
        Doc coverage report: passed
        ---------------------------------------------------

        ## Overall

        Functions: 92% module docs, 85% function docs

        ## Detailed

        lib/quality.ex: 100%
        lib/quality/config.ex: 87%
        lib/quality/stages/format.ex: 90%
        """

        {output, 0}
      end)

      :ok
    end

    test "returns success" do
      result = Doctor.run([])

      assert result.name == "Doctor"
      assert result.status == :ok
      assert result.summary == "Passed"
      assert is_integer(result.duration_ms)
      assert result.duration_ms >= 0
    end
  end

  describe "run/1 - failing documentation" do
    setup do
      System
      |> expect(:cmd, fn "mix", ["doctor", "--raise"], _opts ->
        output = """
        Doctor file found. Loading configuration.

        ---------------------------------------------------
        Doc coverage report: failed
        ---------------------------------------------------

        ## Failed Modules

        lib/quality/stages/test.ex: 45% (below threshold 80%)
        """

        {output, 1}
      end)

      :ok
    end

    test "returns error" do
      result = Doctor.run([])

      assert result.name == "Doctor"
      assert result.status == :error
      assert result.summary == "Documentation coverage below threshold"
    end
  end

  describe "run/1 - summary_only mode" do
    test "uses --summary flag" do
      System
      |> expect(:cmd, fn "mix", ["doctor", "--raise", "--summary"], _opts ->
        {"Doc coverage: 92.5%", 0}
      end)

      result = Doctor.run(doctor: [summary_only: true])

      assert result.status == :ok
    end

    test "omits --summary flag by default" do
      System
      |> expect(:cmd, fn "mix", ["doctor", "--raise"], _opts ->
        {"Passed", 0}
      end)

      result = Doctor.run([])

      assert result.status == :ok
    end
  end

  describe "run/1 - timing" do
    setup do
      System
      |> expect(:cmd, fn "mix", ["doctor", "--raise"], _opts ->
        Process.sleep(10)
        {"Passed", 0}
      end)

      :ok
    end

    test "records execution duration" do
      result = Doctor.run([])

      assert result.duration_ms >= 10
      assert result.duration_ms < 5_000
    end
  end
end
