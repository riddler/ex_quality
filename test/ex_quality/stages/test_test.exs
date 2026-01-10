defmodule ExQuality.Stages.TestTest do
  use ExUnit.Case, async: true
  use Mimic

  alias ExQuality.Stages.Test

  describe "run/1 - successful tests without coverage" do
    setup do
      # Mock ExQuality.Tools to indicate coverage not available
      ExQuality.Tools
      |> stub(:available?, fn :coverage -> false end)

      # Mock successful test run
      System
      |> expect(:cmd, fn "mix", ["test"], _opts ->
        output = """
        ...........

        Finished in 2.3 seconds (0.5s async, 1.8s sync)
        124 tests, 0 failures

        Randomized with seed 123456
        """

        {output, 0}
      end)

      :ok
    end

    test "returns success result with test counts" do
      result = Test.run([])

      assert result.name == "Tests"
      assert result.status == :ok
      assert result.stats.test_count == 124
      assert result.stats.passed_count == 124
      assert result.stats.failed_count == 0
      assert result.summary == "124 of 124 passed"
      assert is_integer(result.duration_ms)
      assert result.duration_ms >= 0
    end
  end

  describe "run/1 - successful tests with coverage" do
    setup do
      # Mock ExQuality.Tools to indicate coverage available
      ExQuality.Tools
      |> stub(:available?, fn :coverage -> true end)

      # Mock successful coveralls run
      System
      |> expect(:cmd, fn "mix", ["coveralls"], _opts ->
        output = """
        ...........

        Finished in 2.3 seconds (0.5s async, 1.8s sync)
        124 tests, 0 failures

        Randomized with seed 123456
        ----------------
        COV    FILE                                        LINES RELEVANT   MISSED
        100.0% lib/quality.ex                                16        2        0
         87.5% lib/quality/config.ex                         89       24        3
        [TOTAL]  85.2%
        ----------------
        """

        {output, 0}
      end)

      :ok
    end

    test "returns success with coverage percentage" do
      result = Test.run([])

      assert result.name == "Tests"
      assert result.status == :ok
      assert result.stats.test_count == 124
      assert result.stats.passed_count == 124
      assert result.stats.failed_count == 0
      assert result.stats.coverage == 85.2
      assert result.summary == "124 of 124 passed, 85.2% coverage"
    end
  end

  describe "run/1 - failed tests" do
    setup do
      # Mock ExQuality.Tools to indicate coverage not available
      ExQuality.Tools
      |> stub(:available?, fn :coverage -> false end)

      # Mock failed test run
      System
      |> expect(:cmd, fn "mix", ["test"], _opts ->
        output = """
        ...........F..F..F

        Finished in 2.3 seconds (0.5s async, 1.8s sync)
        124 tests, 3 failures

        Failed tests:

          1) test handles error case (MyAppTest)
             test/my_app_test.exs:42
             Expected true, got false

          2) test validates input (MyAppTest)
             test/my_app_test.exs:55
             Assertion failed

          3) test processes data (MyAppTest)
             test/my_app_test.exs:68
             Expected 5, got 4
        """

        {output, 1}
      end)

      :ok
    end

    test "returns error with failure count" do
      result = Test.run([])

      assert result.name == "Tests"
      assert result.status == :error
      assert result.stats.test_count == 124
      assert result.stats.passed_count == 121
      assert result.stats.failed_count == 3
      assert result.summary == "3 of 124 failed"
      assert result.output =~ "test/my_app_test.exs:42"
    end
  end

  describe "run/1 - coverage below threshold" do
    setup do
      # Mock ExQuality.Tools to indicate coverage available
      ExQuality.Tools
      |> stub(:available?, fn :coverage -> true end)

      # Mock coveralls run with low coverage
      System
      |> expect(:cmd, fn "mix", ["coveralls"], _opts ->
        output = """
        Finished in 2.3 seconds
        124 tests, 0 failures

        ----------------
        [TOTAL]  65.5%
        ----------------

        Coverage threshold not met: 65.5% < 80.0%
        """

        {output, 1}
      end)

      :ok
    end

    test "returns error with coverage stats" do
      result = Test.run([])

      assert result.name == "Tests"
      assert result.status == :error
      assert result.stats.test_count == 124
      assert result.stats.passed_count == 124
      assert result.stats.failed_count == 0
      assert result.stats.coverage == 65.5
      # When no tests failed but coverage is low and coverage_required isn't set,
      # the summary defaults to "Tests failed"
      # (coverage_required would need to be read from coveralls.json or mix.exs)
      assert result.summary == "Tests failed"
    end
  end

  describe "run/1 - quick mode" do
    setup do
      # Mock ExQuality.Tools to indicate coverage available
      ExQuality.Tools
      |> stub(:available?, fn :coverage -> true end)

      # In quick mode, should run mix test instead of coveralls
      System
      |> expect(:cmd, fn "mix", ["test"], _opts ->
        output = """
        Finished in 2.3 seconds
        124 tests, 0 failures
        """

        {output, 0}
      end)

      :ok
    end

    test "uses mix test instead of coveralls" do
      config = [quick: true]
      result = Test.run(config)

      assert result.status == :ok
      # Should not have coverage in stats
      refute Map.has_key?(result.stats, :coverage)
    end
  end

  describe "run/1 - tests with excluded tests" do
    setup do
      # Mock ExQuality.Tools to indicate coverage not available
      ExQuality.Tools
      |> stub(:available?, fn :coverage -> false end)

      # Mock test run with excluded tests
      System
      |> expect(:cmd, fn "mix", ["test"], _opts ->
        output = """
        Finished in 2.3 seconds
        203 tests, 0 failures, 79 excluded

        Randomized with seed 123456
        """

        {output, 0}
      end)

      :ok
    end

    test "parses test count correctly with exclusions" do
      result = Test.run([])

      assert result.status == :ok
      # Should parse total tests correctly even with exclusions
      assert result.stats.test_count == 203
      assert result.stats.passed_count == 203
      assert result.stats.failed_count == 0
    end
  end

  describe "run/1 - parsing edge cases" do
    setup do
      ExQuality.Tools
      |> stub(:available?, fn :coverage -> false end)

      :ok
    end

    test "handles output with no test count" do
      System
      |> expect(:cmd, fn "mix", ["test"], _opts ->
        output = """
        Some unexpected output format
        """

        {output, 0}
      end)

      result = Test.run([])

      # Should not crash, stats may be empty
      assert result.status == :ok
      assert is_map(result.stats)
    end

    test "handles malformed coverage output" do
      ExQuality.Tools
      |> stub(:available?, fn :coverage -> true end)

      System
      |> expect(:cmd, fn "mix", ["coveralls"], _opts ->
        output = """
        Finished in 2.3 seconds
        124 tests, 0 failures

        Coverage data missing
        """

        {output, 0}
      end)

      result = Test.run([])

      # Should not crash
      assert result.status == :ok
      # Coverage may not be in stats
      refute Map.has_key?(result.stats, :coverage)
    end
  end

  describe "run/1 - timing" do
    setup do
      ExQuality.Tools
      |> stub(:available?, fn :coverage -> false end)

      System
      |> expect(:cmd, fn "mix", ["test"], _opts ->
        # Simulate test run time
        Process.sleep(10)

        output = """
        Finished in 0.5 seconds
        124 tests, 0 failures
        """

        {output, 0}
      end)

      :ok
    end

    test "records execution duration" do
      result = Test.run([])

      assert result.duration_ms >= 10
      assert result.duration_ms < 5_000
    end
  end

  describe "run/1 - format test counts" do
    setup do
      ExQuality.Tools
      |> stub(:available?, fn :coverage -> false end)

      :ok
    end

    test "formats singular test" do
      System
      |> expect(:cmd, fn "mix", ["test"], _opts ->
        output = """
        Finished in 0.1 seconds
        1 test, 0 failures
        """

        {output, 0}
      end)

      result = Test.run([])

      assert result.stats.test_count == 1
      assert result.summary == "1 of 1 passed"
    end

    test "formats plural tests" do
      System
      |> expect(:cmd, fn "mix", ["test"], _opts ->
        output = """
        Finished in 2.3 seconds
        124 tests, 0 failures
        """

        {output, 0}
      end)

      result = Test.run([])

      assert result.stats.test_count == 124
      assert result.summary == "124 of 124 passed"
    end
  end
end
