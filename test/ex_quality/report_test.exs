defmodule ExQuality.ReportTest do
  use ExUnit.Case, async: true

  doctest ExQuality.Report

  alias ExQuality.Finding
  alias ExQuality.Report
  alias ExQuality.Stage

  defp result(overrides) do
    Map.merge(
      %{
        name: "Credo",
        status: :ok,
        output: "",
        stats: %{},
        summary: "No issues",
        duration_ms: 42
      },
      Map.new(overrides)
    )
  end

  describe "build/2" do
    test "reports the run's status, duration and version" do
      report = Report.build([result(status: :ok)], 1234)

      assert report.status == "ok"
      assert report.duration_ms == 1234
      assert report.version == to_string(Application.spec(:ex_quality, :vsn))
    end

    test "is an error when any stage failed" do
      results = [result(status: :ok), result(name: "Tests", status: :error)]

      assert Report.build(results, 1).status == "error"
    end

    test "a skipped stage does not make the run an error" do
      results = [result(status: :ok), Stage.skipped("Dialyzer", "--quick")]

      assert Report.build(results, 1).status == "ok"
    end

    test "keeps the stages in the order they were given" do
      results = [result(name: "Format"), result(name: "Compile"), result(name: "Tests")]

      assert Enum.map(Report.build(results, 1).stages, & &1.name) ==
               ["Format", "Compile", "Tests"]
    end

    test "a skipped stage carries its reason in summary, like every other status" do
      [stage] = Report.build([Stage.skipped("Dialyzer", "--quick")], 1).stages

      assert stage.status == "skipped"
      assert stage.summary == "--quick"
      assert stage.findings == []
    end
  end

  describe "findings" do
    test "are reported per stage" do
      finding = %Finding{
        file: "lib/user.ex",
        line: 42,
        column: 3,
        app: :web,
        severity: :warning,
        check: "readability",
        message: "Modules should have a @moduledoc tag."
      }

      [stage] =
        Report.build([result(status: :error, summary: "1 issue", findings: [finding])], 1).stages

      assert [
               %{
                 file: "lib/user.ex",
                 line: 42,
                 column: 3,
                 app: "web",
                 severity: "warning",
                 check: "readability",
                 message: "Modules should have a @moduledoc tag."
               }
             ] = stage.findings
    end

    test "an absent app stays null rather than becoming a string" do
      finding = %Finding{file: "lib/user.ex", message: "boom"}

      [stage] = Report.build([result(findings: [finding])], 1).stages

      assert [%{app: nil, line: nil, column: nil}] = stage.findings
    end
  end

  describe "output" do
    test "a failing stage that parsed nothing carries its tool output" do
      results = [result(status: :error, output: "** (CompileError) boom\n")]

      [stage] = Report.build(results, 1).stages

      assert stage.output == "** (CompileError) boom\n"
    end

    test "a failing stage with findings carries those instead" do
      finding = %Finding{file: "lib/user.ex", message: "boom"}
      results = [result(status: :error, output: "raw text", findings: [finding])]

      [stage] = Report.build(results, 1).stages

      refute Map.has_key?(stage, :output)
      assert length(stage.findings) == 1
    end

    test "a passing stage's chatter is not carried" do
      [stage] = Report.build([result(status: :ok, output: "lots of noise")], 1).stages

      refute Map.has_key?(stage, :output)
    end
  end

  describe "stats" do
    test "are carried through as-is" do
      results = [result(stats: %{test_count: 4180, failed_count: 3, coverage: 87.3})]

      [stage] = Report.build(results, 1).stages

      assert stage.stats == %{test_count: 4180, failed_count: 3, coverage: 87.3}
    end

    test "per-app pairs become an object, because JSON has no tuples" do
      results = [result(stats: %{failures_by_app: [{"web", 3}, {"core", 1}]})]

      [stage] = Report.build(results, 1).stages

      assert stage.stats.failures_by_app == %{"web" => 3, "core" => 1}
    end
  end

  describe "encode!/1" do
    test "round-trips a report with findings and per-app stats" do
      finding = %Finding{file: "lib/user.ex", line: 42, app: :core, message: "boom"}

      json =
        [result(status: :error, findings: [finding], stats: %{coverage_by_app: [{"core", 72.1}]})]
        |> Report.build(99)
        |> Report.encode!()

      assert String.ends_with?(json, "\n")

      assert %{
               "status" => "error",
               "duration_ms" => 99,
               "stages" => [
                 %{
                   "name" => "Credo",
                   "findings" => [%{"file" => "lib/user.ex", "line" => 42, "app" => "core"}],
                   "stats" => %{"coverage_by_app" => %{"core" => 72.1}}
                 }
               ]
             } = Jason.decode!(json)
    end
  end
end
