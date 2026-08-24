defmodule Mix.Tasks.Quality.VerifyTest do
  use ExUnit.Case, async: false
  use Mimic

  import ExUnit.CaptureIO

  alias ExQuality.Report
  alias ExQuality.Stage
  alias Mix.Tasks.Quality.Verify

  # The attestation reads the same report `Mix.Tasks.Quality.execute/1`
  # builds, so the fixtures are built by `Report.build/3` rather than by hand:
  # a shape drift between the two would fail here first.
  defp report(stages, config \\ []) do
    Report.build(stages, 100, config)
  end

  defp runner(report, config \\ []) do
    fn _args -> %{report: report, config: config, failure: nil} end
  end

  defp ok(name, stats \\ %{}) do
    %{name: name, status: :ok, output: "", stats: stats, summary: "Passed", duration_ms: 1}
  end

  defp failed(name) do
    %{name: name, status: :error, output: "boom", stats: %{}, summary: "Failed", duration_ms: 1}
  end

  defp tests(stats \\ %{coverage: 88.3}, meta \\ nil) do
    result = ok("Tests", stats)

    if meta, do: Map.put(result, :meta, meta), else: result
  end

  defp full_green do
    [ok("Format"), ok("Compile"), ok("Credo"), tests()]
  end

  describe "a run that attests" do
    test "a full green run attests, naming what was verified" do
      captured = capture_io(fn -> Verify.run([], runner(report(full_green()))) end)

      assert captured =~ "Full gate green: scope all, no profile, 4 stages considered."
    end

    test "a project-level skip attests and is named as a standing gap" do
      stages = full_green() ++ [Stage.skipped("Sobelow", ":sobelow not installed", :project)]

      captured = capture_io(fn -> Verify.run([], runner(report(stages))) end)

      assert captured =~ "Full gate green"
      assert captured =~ "Not checked by this project at all: Sobelow (:sobelow not installed)"
    end

    test "an unlabelled skip defaults to a project one, the conservative direction" do
      # A custom stage that skipped itself without the kind: it must not read
      # as a narrowing that attests silently, and must not fail the run.
      unlabelled = %{
        name: "Nullability",
        status: :skipped,
        output: "",
        stats: %{},
        summary: "test database is not migrated",
        duration_ms: 0
      }

      captured =
        capture_io(fn -> Verify.run([], runner(report(full_green() ++ [unlabelled]))) end)

      assert captured =~ "Full gate green"

      assert captured =~
               "Not checked by this project at all: Nullability (test database is not migrated)"
    end

    test "a scope that fell back to the full suite attests" do
      # The root scope is already "all" for a fallback run - the run genuinely
      # ran everything - and this pins that, because the naive reading of
      # requested_scope makes it look like a check someone should "fix".
      meta = %{
        scope: "all",
        requested_scope: "changed",
        fallback_reason: "no test files map to the changed files"
      }

      stages = [ok("Format"), ok("Compile"), tests(%{coverage: 90.1}, meta)]

      captured = capture_io(fn -> Verify.run([], runner(report(stages))) end)

      assert captured =~ "Full gate green"
    end

    test "a project that never measures coverage attests, with the gap named" do
      stages = [ok("Format"), ok("Compile"), tests(%{})]
      config = [test: [coverage: false]]

      captured = capture_io(fn -> Verify.run([], runner(report(stages, config), config)) end)

      assert captured =~ "Full gate green"
      assert captured =~ "Coverage is not measured by this project (test: [coverage: false])"
    end
  end

  describe "a run that does not attest" do
    test "a red gate names the failing stages" do
      stages = [ok("Format"), failed("Credo"), failed("Tests")]

      assert_raise Mix.Error, ~r/the gate is red \(Credo, Tests failed\)/, fn ->
        capture_io(fn -> Verify.run([], runner(report(stages))) end)
      end
    end

    test "a profile disqualifies the run" do
      assert_raise Mix.Error, ~r/run used profile :loop/, fn ->
        capture_io(fn -> Verify.run([], runner(report(full_green(), profile: :loop))) end)
      end
    end

    test "a narrowed test scope disqualifies the run" do
      stages = [ok("Format"), ok("Compile"), tests(%{}, %{scope: "changed"})]

      assert_raise Mix.Error, ~r/test scope was "changed"/, fn ->
        capture_io(fn -> Verify.run([], runner(report(stages))) end)
      end
    end

    test "quick mode disqualifies the run" do
      assert_raise Mix.Error, ~r/narrowed by --quick/, fn ->
        capture_io(fn ->
          Verify.run([], runner(report(full_green(), quick: true), quick: true))
        end)
      end
    end

    test "a stage skipped for a run-level reason disqualifies the run" do
      stages = full_green() ++ [Stage.skipped("Dialyzer", "--skip-dialyzer", :run)]

      assert_raise Mix.Error, ~r/Dialyzer was skipped \(--skip-dialyzer\)/, fn ->
        capture_io(fn -> Verify.run([], runner(report(stages))) end)
      end
    end

    test "missing coverage on an otherwise full run disqualifies it" do
      # The project measures coverage (excoveralls is a dep of this repo), so
      # a full green run whose Tests stage carries no number was narrowed by
      # something - a profile's `coverage: false`, say - that no other check
      # names.
      stages = [ok("Format"), ok("Compile"), tests(%{})]

      assert_raise Mix.Error, ~r/coverage was not measured/, fn ->
        capture_io(fn -> Verify.run([], runner(report(stages))) end)
      end
    end

    test "every reason is named at once, not just the first" do
      stages = full_green() ++ [Stage.skipped("Dialyzer", "--quick", :run)]

      message =
        assert_raise(Mix.Error, fn ->
          capture_io(fn -> Verify.run([], runner(report(stages, profile: :loop))) end)
        end).message

      assert message =~ "run used profile :loop"
      assert message =~ "Dialyzer was skipped (--quick)"
      assert message =~ " and "
    end

    test "a runner that produced no report is its own error, not a red gate" do
      assert_raise Mix.Error, ~r/produced no report/, fn ->
        Verify.run([], fn _args -> %{report: nil, config: []} end)
      end
    end
  end

  describe "over a real run" do
    setup do
      ExQuality.Tools
      |> stub(:detect, fn ->
        %{
          credo: false,
          dialyzer: false,
          doctor: false,
          docs: false,
          gettext: false,
          coverage: false,
          audit: false,
          sobelow: false
        }
      end)
      |> stub(:available?, fn _tool -> false end)

      System
      |> stub(:cmd, fn
        "mix", ["test" | _], _opts -> {"1 tests, 0 failures\n", 0}
        _cmd, _args, _opts -> {"", 0}
      end)

      :ok
    end

    test "the default runner runs the gate and attests over it" do
      captured = capture_io(fn -> Verify.run([]) end)

      # The gate's own stream printed first, then the attestation over it.
      assert captured =~ "All quality checks passed"
      assert captured =~ "Full gate green: scope all, no profile, 10 stages considered."

      # The stages this project never checks are standing gaps, named.
      assert captured =~ "Not checked by this project at all:"
      assert captured =~ "Credo (:credo not installed)"

      # No coverage tool detected, so the number's absence is a gap too.
      assert captured =~ "Coverage is not measured by this project"
    end

    test "the same flags reach the run, and a narrowing one fails the attestation" do
      assert_raise Mix.Error, ~r/Not a full gate/, fn ->
        capture_io(fn -> Verify.run(["--quick"]) end)
      end
    end
  end
end
