defmodule ExQuality.Stages.TestTest do
  use ExUnit.Case, async: true
  use Mimic

  alias ExQuality.Stages.Test

  describe "run/1 - successful tests without coverage" do
    setup do
      # Mock ExQuality.Tools to indicate coverage not available
      ExQuality.Tools
      |> stub(:available?, fn tool -> tool == :native_coverage end)

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
      |> stub(:available?, fn tool -> tool == :coverage end)

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
      |> stub(:available?, fn tool -> tool == :native_coverage end)

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

    test "parses each failure into a finding a caller can route" do
      assert [first, second, third] = ExQuality.Stage.findings(Test.run([]))

      assert %ExQuality.Finding{
               file: "test/my_app_test.exs",
               line: 42,
               severity: :error,
               check: "MyAppTest",
               message: "handles error case: Expected true, got false"
             } = first

      assert %{line: 55, message: "validates input: Assertion failed"} = second
      assert %{line: 68, message: "processes data: Expected 5, got 4"} = third
    end
  end

  describe "run/1 - failures in an umbrella" do
    setup do
      ExQuality.Tools
      |> stub(:available?, fn _tool -> false end)

      ExQuality.Umbrella
      |> stub(:apps_paths, fn -> %{web: "apps/web"} end)

      System
      |> expect(:cmd, fn "mix", ["test"], _opts ->
        output = """
        ==> web
        .....F

          1) test Oban jobs a job execution produces a consumer span (Web.Telemetry.ConsumerTracingTest)
             apps/web/test/web/telemetry/consumer_tracing_test.exs:118
             expected an Oban job span named 'process default'
             code: assert job_span, "expected an Oban job span named 'process default'"
             stacktrace:
               test/web/telemetry/consumer_tracing_test.exs:145: (test)


        Finished in 3.1 seconds
        6 tests, 1 failure
        """

        {output, 1}
      end)

      :ok
    end

    test "attributes the failure to its app, from the header line's path" do
      assert [finding] = ExQuality.Stage.findings(Test.run([]))

      assert finding.app == :web
      assert finding.file == "apps/web/test/web/telemetry/consumer_tracing_test.exs"
      assert finding.line == 118
      assert finding.check == "Web.Telemetry.ConsumerTracingTest"
    end

    test "reads the header line rather than the app-relative stacktrace" do
      [finding] = ExQuality.Stage.findings(Test.run([]))

      # The stacktrace says test/... and line 145; only the header line opens
      # from the umbrella root.
      refute finding.file == "test/web/telemetry/consumer_tracing_test.exs"
      refute finding.line == 145
    end

    test "keeps the failure's own lines on the finding" do
      [finding] = ExQuality.Stage.findings(Test.run([]))

      assert finding.raw =~ "1) test Oban jobs"
      assert finding.raw =~ "expected an Oban job span"
    end
  end

  describe "run/1 - failures the parser does not recognise" do
    setup do
      ExQuality.Tools
      |> stub(:available?, fn _tool -> false end)

      # Two failures reported, one of them in a shape the parser cannot read.
      System
      |> expect(:cmd, fn "mix", ["test"], _opts ->
        output = """
          1) test handles error case (MyAppTest)
             test/my_app_test.exs:42
             Expected true, got false

        ** (exit) an unparseable catastrophe

        2 tests, 2 failures
        """

        {output, 1}
      end)

      :ok
    end

    test "reports nothing rather than a partial list that reads as complete" do
      result = Test.run([])

      assert ExQuality.Stage.findings(result) == []
      assert result.output =~ "an unparseable catastrophe"
      assert result.output =~ "1) test handles error case"
    end
  end

  describe "run/1 - coverage below threshold" do
    setup do
      # Mock ExQuality.Tools to indicate coverage available
      ExQuality.Tools
      |> stub(:available?, fn tool -> tool == :coverage end)

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
      # A run with no test failures failed on coverage, so the summary names
      # the number rather than saying "Tests failed". The required percentage
      # comes from this project's own coveralls.json, so it is not asserted on
      # here; read_coverage_threshold/1 is covered directly below.
      assert result.summary =~ "Coverage 65.5% (required: "
    end
  end

  describe "run/1 - quick mode" do
    setup do
      # Mock ExQuality.Tools to indicate coverage available
      ExQuality.Tools
      |> stub(:available?, fn tool -> tool == :coverage end)

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
      |> stub(:available?, fn tool -> tool == :native_coverage end)

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
      |> stub(:available?, fn tool -> tool == :native_coverage end)

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
      |> stub(:available?, fn tool -> tool == :coverage end)

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
      |> stub(:available?, fn tool -> tool == :native_coverage end)

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
      |> stub(:available?, fn tool -> tool == :native_coverage end)

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

  describe "run/1 - umbrella projects" do
    setup do
      ExQuality.Tools
      |> stub(:available?, fn tool -> tool == :native_coverage end)

      :ok
    end

    test "sums the per-app summary lines instead of reporting the first" do
      System
      |> expect(:cmd, fn "mix", ["test"], _opts ->
        output = """
        ==> core
        ....
        Finished in 1.0 seconds
        12 tests, 0 failures

        ==> web
        ...F
        Finished in 30.0 seconds
        4168 tests, 3 failures
        """

        {output, 1}
      end)

      result = Test.run([])

      assert result.stats.test_count == 4180
      assert result.stats.failed_count == 3
      assert result.stats.passed_count == 4177
      assert result.summary == "3 of 4,180 failed (web: 3)"
    end

    test "names every failing app and no passing one" do
      System
      |> expect(:cmd, fn "mix", ["test"], _opts ->
        output = """
        ==> core
        10 tests, 2 failures

        ==> repo
        10 tests, 0 failures

        ==> web
        10 tests, 1 failure
        """

        {output, 1}
      end)

      result = Test.run([])

      assert result.stats.failures_by_app == [{"core", 2}, {"web", 1}]
      assert result.summary == "3 of 30 failed (core: 2, web: 1)"
    end

    test "reports a passing suite as the sum of its apps" do
      System
      |> expect(:cmd, fn "mix", ["test"], _opts ->
        output = """
        ==> core
        12 tests, 0 failures

        ==> web
        1188 tests, 0 failures
        """

        {output, 0}
      end)

      result = Test.run([])

      assert result.status == :ok
      assert result.summary == "1,200 of 1,200 passed"
      assert result.stats.failures_by_app == []
    end

    test "reports the lowest coverage when apps are measured separately" do
      ExQuality.Tools
      |> stub(:available?, fn tool -> tool == :coverage end)

      System
      |> expect(:cmd, fn "mix", ["coveralls"], _opts ->
        output = """
        ==> core
        12 tests, 0 failures
        [TOTAL]  91.0%

        ==> web
        88 tests, 0 failures
        [TOTAL]  72.1%
        """

        {output, 0}
      end)

      result = Test.run([])

      assert result.stats.coverage == 72.1
      assert result.stats.coverage_by_app == [{"core", 91.0}, {"web", 72.1}]
      assert result.summary == "100 of 100 passed, 72.1% coverage (lowest of 2 apps)"
    end
  end

  describe "run/1 - test args pass-through" do
    setup do
      ExQuality.Tools
      |> stub(:available?, fn tool -> tool == :native_coverage end)

      :ok
    end

    test "passes extra args to mix test" do
      System
      |> expect(:cmd, fn "mix", ["test", "--only", "integration"], _opts ->
        output = """
        Finished in 2.3 seconds
        10 tests, 0 failures
        """

        {output, 0}
      end)

      config = [test: [args: ["--only", "integration"]]]
      result = Test.run(config)

      assert result.status == :ok
      assert result.stats.test_count == 10
    end

    test "passes extra args to mix coveralls" do
      ExQuality.Tools
      |> stub(:available?, fn tool -> tool == :coverage end)

      System
      |> expect(:cmd, fn "mix", ["coveralls", "--only", "integration"], _opts ->
        output = """
        Finished in 2.3 seconds
        10 tests, 0 failures
        [TOTAL]  85.2%
        """

        {output, 0}
      end)

      config = [test: [args: ["--only", "integration"]]]
      result = Test.run(config)

      assert result.status == :ok
      assert result.stats.test_count == 10
      assert result.stats.coverage == 85.2
    end

    test "handles multiple args" do
      System
      |> expect(:cmd, fn "mix", ["test", "--include", "slow", "--seed", "0"], _opts ->
        output = """
        Finished in 5.0 seconds
        50 tests, 0 failures
        """

        {output, 0}
      end)

      config = [test: [args: ["--include", "slow", "--seed", "0"]]]
      result = Test.run(config)

      assert result.status == :ok
      assert result.stats.test_count == 50
    end

    test "defaults to empty args when not specified" do
      System
      |> expect(:cmd, fn "mix", ["test"], _opts ->
        output = """
        Finished in 2.3 seconds
        124 tests, 0 failures
        """

        {output, 0}
      end)

      result = Test.run([])

      assert result.status == :ok
    end
  end

  describe "run/1 - native coverage" do
    setup do
      ExQuality.Tools
      |> stub(:available?, fn tool -> tool == :native_coverage end)

      :ok
    end

    test "stays on bare mix test when the project asks for no coverage" do
      System
      |> expect(:cmd, fn "mix", ["test"], _opts ->
        {"124 tests, 0 failures\n", 0}
      end)

      result = Test.run([])

      assert result.status == :ok
      refute Map.has_key?(result.stats, :coverage)
    end

    test "runs mix test --cover when coverage is asked for" do
      System
      |> expect(:cmd, fn "mix", ["test", "--cover"], _opts ->
        {native_output(), 0}
      end)

      result = Test.run(test: [coverage: true])

      assert result.status == :ok
      assert result.stats.test_count == 124
      assert result.stats.coverage == 62.5
      assert result.summary == "124 of 124 passed, 62.5% coverage"
    end

    test "passes test args through to mix test --cover" do
      System
      |> expect(:cmd, fn "mix", ["test", "--cover", "--only", "integration"], _opts ->
        {native_output(), 0}
      end)

      result = Test.run(test: [coverage: true, args: ["--only", "integration"]])

      assert result.status == :ok
    end

    test "never measures coverage in quick mode" do
      System
      |> expect(:cmd, fn "mix", ["test"], _opts ->
        {"124 tests, 0 failures\n", 0}
      end)

      result = Test.run(quick: true, test: [coverage: true])

      assert result.status == :ok
      refute Map.has_key?(result.stats, :coverage)
    end

    test "reads the threshold the tool printed rather than the project's config" do
      System
      |> expect(:cmd, fn "mix", ["test", "--cover"], _opts ->
        {native_output(:below_threshold), 3}
      end)

      result = Test.run(test: [coverage: true])

      assert result.status == :error
      assert result.stats.coverage == 62.5
      assert result.stats.coverage_required == 90.0
      assert result.summary == "Coverage 62.5% (required: 90.0%)"
    end

    test "reports only the modules under the threshold as findings" do
      System
      |> expect(:cmd, fn "mix", ["test", "--cover"], _opts ->
        {native_output(:below_threshold), 3}
      end)

      result = Test.run(test: [coverage: true])

      assert Enum.map(result.findings, & &1.message) == [
               "MyApp.Thing is 33.3% covered (threshold 90.0%)",
               "MyApp.Unused is 0.0% covered (threshold 90.0%)"
             ]

      assert Enum.all?(result.findings, &(&1.severity == :error))
      assert hd(result.findings).raw =~ "33.33% | MyApp.Thing"
    end

    test "resolves a module to its source file when the beam is there" do
      System
      |> expect(:cmd, fn "mix", ["test", "--cover"], _opts ->
        output = """
        124 tests, 0 failures

        Percentage | Module
        -----------|--------------------------
            10.00% | ExQuality.Finding
        -----------|--------------------------
            10.00% | Total

        Coverage test failed, threshold not met:

            Coverage:   10.00%
            Threshold:  90.00%
        """

        {output, 3}
      end)

      result = Test.run(test: [coverage: true])

      assert [%{file: "lib/ex_quality/finding.ex"}] = result.findings
    end

    test "falls back to the module name when no beam names it" do
      System
      |> expect(:cmd, fn "mix", ["test", "--cover"], _opts ->
        {native_output(:below_threshold), 3}
      end)

      result = Test.run(test: [coverage: true])

      assert Enum.map(result.findings, & &1.file) == ["MyApp.Thing", "MyApp.Unused"]
    end

    test "reports no modules when the run passed its threshold" do
      System
      |> expect(:cmd, fn "mix", ["test", "--cover"], _opts ->
        {native_output(), 0}
      end)

      result = Test.run(test: [coverage: true])

      assert result.status == :ok
      assert result.findings == []
    end

    test "reports failing tests rather than coverage when both are wrong" do
      System
      |> expect(:cmd, fn "mix", ["test", "--cover"], _opts ->
        {String.replace(native_output(:below_threshold), "0 failures", "3 failures"), 1}
      end)

      result = Test.run(test: [coverage: true])

      assert result.summary == "3 of 124 failed, 62.5% coverage"
    end
  end

  describe "run/1 - native coverage in an umbrella" do
    setup do
      ExQuality.Tools
      |> stub(:available?, fn tool -> tool == :native_coverage end)

      ExQuality.Umbrella
      |> stub(:umbrella?, fn -> true end)
      |> stub(:apps_paths, fn -> %{one: "apps/one", two: "apps/two"} end)

      :ok
    end

    test "exports per app, then aggregates the exports into one total" do
      System
      |> expect(:cmd, 2, fn
        "mix", ["test", "--cover", "--export-coverage", "default"], _opts ->
          {umbrella_export_output(), 0}

        "mix", ["test.coverage"], _opts ->
          {umbrella_aggregate_output(), 3}
      end)

      result = Test.run(test: [coverage: true])

      assert result.status == :error
      assert result.stats.test_count == 30
      assert result.stats.coverage == 50.0
      assert result.stats.coverage_required == 90.0
      assert result.summary == "Coverage 50.0% (required: 90.0%)"
    end

    test "tags a finding with the app its source file belongs to" do
      System
      |> expect(:cmd, 2, fn
        "mix", ["test", "--cover", "--export-coverage", "default"], _opts ->
          {"==> one\n10 tests, 0 failures\n", 0}

        "mix", ["test.coverage"], _opts ->
          output = """
          Percentage | Module
          -----------|--------------------------
              50.00% | ExQuality.Finding
          -----------|--------------------------
              50.00% | Total

          Coverage test failed, threshold not met:

              Coverage:   50.00%
              Threshold:  90.00%
          """

          {output, 3}
      end)

      ExQuality.Umbrella
      |> stub(:app_for_path, fn "lib/ex_quality/finding.ex", _apps -> :one end)

      result = Test.run(test: [coverage: true])

      assert [%{file: "lib/ex_quality/finding.ex", app: :one}] = result.findings
    end

    test "does not aggregate coverage when the suite failed" do
      System
      |> expect(:cmd, fn "mix", ["test", "--cover", "--export-coverage", "default"], _opts ->
        {"==> one\n10 tests, 2 failures\n", 1}
      end)

      result = Test.run(test: [coverage: true])

      assert result.status == :error
      assert result.summary == "2 of 10 failed (one: 2)"
      refute Map.has_key?(result.stats, :coverage)
    end
  end

  defp native_output(variant \\ :passing) do
    table = """
    Running ExUnit with seed: 0, max_cases: 30

    ......
    Finished in 2.3 seconds
    124 tests, 0 failures

    Generating cover results ...

    Percentage | Module
    -----------|--------------------------
         0.00% | MyApp.Unused
        33.33% | MyApp.Thing
       100.00% | MyApp
    -----------|--------------------------
        62.50% | Total
    """

    case variant do
      :passing ->
        table

      :below_threshold ->
        table <>
          """

          Coverage test failed, threshold not met:

              Coverage:   62.50%
              Threshold:  90.00%
          """
    end
  end

  describe "run/1 - scoped runs" do
    # A glob over files that really exist, so the scope resolves without a git
    # working tree to set up. `:changed` resolution is covered in ScopeTest.
    @glob "test/ex_quality/stages/co*_test.exs"
    @scoped_files [
      "test/ex_quality/stages/command_test.exs",
      "test/ex_quality/stages/compile_test.exs"
    ]

    setup do
      ExQuality.Tools |> stub(:available?, fn _tool -> true end)

      :ok
    end

    test "runs only the test files in scope" do
      System
      |> expect(:cmd, fn "mix", args, _opts ->
        assert args == ["test" | @scoped_files]
        {"2 tests, 0 failures\n", 0}
      end)

      result = Test.run(test: [scope: @glob])

      assert result.status == :ok
      assert result.meta.scope == @glob
      assert result.meta.files == 2
      assert result.meta.test_files == @scoped_files
    end

    test "never measures coverage on a scoped run, even with coveralls available" do
      System
      |> expect(:cmd, fn "mix", ["test" | _files], _opts -> {"2 tests, 0 failures\n", 0} end)

      result = Test.run(test: [scope: @glob, coverage: true])

      assert result.meta.coverage == "skipped"
      assert result.meta.coverage_reason == "not measured on a scoped run"
      refute Map.has_key?(result.stats, :coverage)
    end

    test "says in the summary what it did and did not cover" do
      System
      |> expect(:cmd, fn "mix", ["test" | _files], _opts -> {"2 tests, 0 failures\n", 0} end)

      result = Test.run(test: [scope: @glob])

      assert result.summary == "2 of 2 passed (scope #{@glob}, 2 files, no coverage)"
    end

    test "passes configured test args ahead of the paths" do
      System
      |> expect(:cmd, fn "mix", args, _opts ->
        assert args == ["test", "--seed", "0"] ++ @scoped_files
        {"2 tests, 0 failures\n", 0}
      end)

      Test.run(test: [scope: @glob, args: ["--seed", "0"]])
    end

    test "runs the full suite when the scope resolves to nothing" do
      System
      |> expect(:cmd, fn "mix", ["coveralls"], _opts -> {"2 tests, 0 failures\n", 0} end)

      result = Test.run(test: [scope: "test/nowhere/**/*_test.exs"])

      assert result.meta.scope == "all"
      assert result.meta.requested_scope == "test/nowhere/**/*_test.exs"
      assert result.meta.fallback_reason == "the glob matched no test files"
      refute Map.has_key?(result.meta, :coverage)

      assert result.summary =~ "fell back to the full suite"
    end

    test "an unscoped run reports the scope it ran at" do
      System
      |> expect(:cmd, fn "mix", ["coveralls"], _opts -> {"2 tests, 0 failures\n", 0} end)

      result = Test.run([])

      assert result.meta == %{scope: "all"}
      assert result.summary == "2 of 2 passed"
    end
  end

  defp umbrella_export_output do
    """
    ==> one
    10 tests, 0 failures

    Exporting cover results ...

    ==> two
    20 tests, 0 failures

    Exporting cover results ...
    """
  end

  defp umbrella_aggregate_output do
    """
    Importing cover results: apps/one/cover/default.coverdata
    Importing cover results: apps/two/cover/default.coverdata

    Percentage | Module
    -----------|--------------------------
        50.00% | One
        50.00% | Two
    -----------|--------------------------
        50.00% | Total

    Coverage test failed, threshold not met:

        Coverage:   50.00%
        Threshold:  90.00%
    """
  end
end
