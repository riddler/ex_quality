defmodule Mix.Tasks.Quality.Verify do
  @shortdoc "Runs the gate and attests that it was the full gate"

  @moduledoc """
  Runs `mix quality` and attests that what ran was the *full* gate.

  A green run is not by itself evidence of a green gate. `--profile`,
  `--test-scope`, `--quick`, `--skip` and `--until-first-failure` all produce
  `"status": "ok"`, and each of them checks less. That is the right design for
  the inner loop, but the claim made *about* such a run afterwards is where it
  goes wrong: when an agent runs the gate unattended and reports "gate green"
  into a pull request or a commit message, nobody observed the run, and the
  narrow one and the full one produce the same three words.

  This task is the check nobody has to remember to make:

      mix quality.verify

  It runs the gate - printing exactly what `mix quality` prints - and then
  attests over the same results. It exits 0 when the run attests and non-zero
  when it does not, naming every reason at once:

      Not a full gate: run used profile :loop and Dialyzer was skipped (--quick).

  ## What attests

  A run attests when all of the following hold:

  - every stage passed (`"status": "ok"`);
  - no profile was used;
  - the test scope was `"all"` - a `:changed` scope that fell back to the full
    suite genuinely ran everything, reports `"all"`, and attests;
  - quick mode was off;
  - no stage was skipped for a reason that names *this run* (`skip_kind`
    `"run"`: `--quick`, `--skip`, a profile, `--until-first-failure`);
  - coverage was measured, when the project measures coverage at all.

  A stage skipped for a **project-level** reason (`:sobelow not installed`,
  `disabled in .quality.exs`) does not fail the attestation. It is named in
  the output instead, because it is a standing gap in what the project checks
  at all, and a fuller run cannot close it:

      Full gate green: scope all, no profile, 9 stages considered.
      Not checked by this project at all: Sobelow (:sobelow not installed)

  Those are two different facts, and the reader needs both.

  ## Flags

  Takes the same flags as `mix quality` and passes them through. A flag that
  narrows the run makes the attestation fail, which is the point: run this the
  way CI runs the gate, with no flags. `--report PATH` still writes the
  caller's report where it asked.

  ## What this does not prove

  `mix quality.verify` attests that the run was not narrowed. It cannot attest
  that the gate is *strong*. A project can weaken `.quality.exs` - drop a
  stage, add a permissive profile - or lower a coverage threshold, and then
  attest honestly against the weakened gate. Guarding the gate's own
  configuration is a different mechanism (a config-change guard against a base
  ref), and a caller that treats this attestation as proof of it is claiming
  more than was checked.
  """

  use Mix.Task

  alias ExQuality.Stages.Test, as: TestStage
  alias Mix.Tasks.Quality

  @doc """
  Runs the gate and attests, failing the task when the run does not attest.
  """
  @spec run([String.t()]) :: :ok
  def run(args), do: run(args, &Quality.execute/1)

  @doc false
  # The runner is injectable so tests can attest over a made report without
  # paying for a nested gate run. It takes `mix quality`'s argument list and
  # returns what `Mix.Tasks.Quality.execute/1` returns: the built report and
  # the config the run resolved.
  @spec run([String.t()], ([String.t()] -> %{report: map(), config: keyword()})) :: :ok
  def run(args, runner) do
    %{report: report, config: config} = runner.(args)

    # A red gate still produces a report, so a missing one is not "the gate is
    # red" - it is the runner having nothing to attest over, and the reader
    # needs to be sent to the run, not to the code.
    unless report do
      Mix.raise("The run produced no report, so there is nothing to attest over.")
    end

    Mix.shell().info("")

    case problems(report, config) do
      [] ->
        Mix.shell().info([:green, attested(report)])
        Enum.each(gaps(report, config), &Mix.shell().info/1)

      problems ->
        Mix.raise("Not a full gate: #{sentence(problems)}.")
    end

    :ok
  end

  # Every reason at once, not the first: whoever reads the failure is about to
  # re-run the gate, and should only have to do that once.
  defp problems(report, config) do
    red(report) ++
      profile(report) ++
      scope(report) ++
      quick(config) ++
      narrowed(report.stages) ++
      coverage(report, config)
  end

  defp red(%{status: "ok"}), do: []

  defp red(report) do
    failed = for stage <- report.stages, stage.status == "error", do: stage.name

    ["the gate is red (#{Enum.join(failed, ", ")} failed)"]
  end

  defp profile(%{profile: nil}), do: []
  defp profile(%{profile: profile}), do: ["run used profile :#{profile}"]

  defp scope(%{scope: "all"}), do: []
  defp scope(%{scope: scope}), do: [~s(test scope was "#{scope}")]

  defp quick(config) do
    if Keyword.get(config, :quick, false), do: ["the run was narrowed by --quick"], else: []
  end

  defp narrowed(stages) do
    for stage <- stages, stage.status == "skipped", stage.skip_kind == "run" do
      "#{stage.name} was skipped (#{stage.summary})"
    end
  end

  # Coverage is a narrowing no stage line carries: a scoped run is caught by
  # `scope` and quick mode by `quick`, but `test: [coverage: false]` arriving
  # through a profile, or any future way of dropping the measurement, would
  # otherwise attest. Only a project that measures coverage at all is held to
  # it - a project that never measures has a standing gap, not a narrower run.
  defp coverage(report, config) do
    tests = Enum.find(report.stages, &(&1.name == "Tests"))

    if tests != nil and tests.status == "ok" and TestStage.measures_coverage?(config) and
         not Map.has_key?(tests.stats, :coverage) do
      ["coverage was not measured"]
    else
      []
    end
  end

  defp attested(report) do
    "Full gate green: scope all, no profile, #{length(report.stages)} stages considered."
  end

  # The standing gaps: what this project never checks, which a fuller run
  # cannot close. Saying "full gate green" without them would let the
  # attestation claim more than the project measures.
  defp gaps(report, config) do
    project_skips(report.stages) ++ coverage_gap(config)
  end

  defp project_skips(stages) do
    skips =
      for stage <- stages, stage.status == "skipped", stage.skip_kind == "project" do
        "#{stage.name} (#{stage.summary})"
      end

    case skips do
      [] -> []
      skips -> ["Not checked by this project at all: #{Enum.join(skips, ", ")}"]
    end
  end

  defp coverage_gap(config) do
    if TestStage.measures_coverage?(config) do
      []
    else
      ["Coverage is not measured by this project (#{coverage_gap_reason(config)})"]
    end
  end

  defp coverage_gap_reason(config) do
    if config |> Keyword.get(:test, []) |> Keyword.get(:coverage, :auto) == false do
      "test: [coverage: false]"
    else
      "no coverage tool or threshold configured"
    end
  end

  defp sentence([problem]), do: problem
  defp sentence([first, second]), do: "#{first} and #{second}"

  defp sentence(problems) do
    {rest, [last]} = Enum.split(problems, -1)

    Enum.join(rest, ", ") <> ", and " <> last
  end
end
