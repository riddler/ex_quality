defmodule ExQuality.Report do
  @moduledoc """
  Builds the machine-readable form of a run.

  `mix quality` exits 0 or 1 for the whole run, which tells a caller that
  something failed but not what. A script that wants to route on the result -
  hand the credo findings to one fixer, the test failures to another - would
  otherwise have to scrape the console or re-run the tools.

  A report answers "which stages ran, which failed, and what did they find"
  from the same results the human output is rendered from, so the two streams
  can never disagree.

  ## Shape

      {
        "version": "0.6.0",
        "status": "error",
        "duration_ms": 48213,
        "profile": "loop",
        "scope": "changed",
        "base_ref": "origin/main",
        "stages": [
          {
            "name": "Credo",
            "status": "error",
            "summary": "5 issues (2 readability, 3 design)",
            "duration_ms": 412,
            "stats": {"issue_count": 5},
            "findings": [
              {
                "file": "lib/user.ex", "line": 42, "column": 3,
                "app": "web", "severity": "info",
                "check": "Credo.Check.Readability.ModuleDoc",
                "message": "Modules should have a @moduledoc tag."
              }
            ]
          },
          {
            "name": "Dialyzer", "status": "skipped",
            "summary": "--quick", "skip_kind": "run",
            "duration_ms": 0, "stats": {}, "findings": []
          }
        ]
      }

  Every stage carries the same keys whatever its status, so a consumer reads
  one field for the explanation rather than branching: a skipped stage puts its
  reason in `summary`, exactly as `ExQuality.Stage.skipped/3` records it.

  `skip_kind` is `null` unless the stage was skipped, `"run"` when the skip
  names this run (a full `mix quality` closes it) and `"project"` when it
  names the project (a fuller run cannot close it). It is what lets a consumer
  such as `mix quality.verify` tell the two apart without parsing the reason's
  prose. A skipped stage that carries no kind - a custom stage that has not
  opted in - reports `"project"`, the conservative direction. See
  `t:ExQuality.Stage.skip_kind/0`.

  A stage that failed without producing findings carries its tool's full output
  under `output` instead, mirroring the human renderer. Findings are the parsed
  form; `output` is the fallback, and one of the two is always present for a
  failure.

  ## How much the run covered

  `profile`, `scope` and `base_ref` are always present at the root, `null` when
  they do not apply. They are what makes `"status": "ok"` interpretable: a green
  run scoped to three test files is not the same claim as a green full run, and a
  caller that lowers a recorded coverage figure or moves a baseline on a green
  run has to be able to refuse the narrow one. The test stage repeats them, plus
  the files it ran, in its own object. See `ExQuality.Scope`.
  """

  alias ExQuality.Finding
  alias ExQuality.Scope
  alias ExQuality.Stage

  @type t :: %{
          version: String.t(),
          status: String.t(),
          duration_ms: non_neg_integer(),
          profile: String.t() | nil,
          scope: String.t() | nil,
          base_ref: String.t() | nil,
          stages: [map()]
        }

  @doc """
  Builds a report from the results of a run.

  `duration_ms` is the wall clock time of the whole run, which is not the sum
  of the stage durations because the analysis stages run in parallel.

  `config` is the run's loaded config, used for the root `profile` and for the
  scope when the test stage did not run to report one of its own.

      iex> alias ExQuality.{Report, Stage}
      iex> report = Report.build([Stage.skipped("Dialyzer", "--quick")], 12)
      iex> {report.status, report.duration_ms, length(report.stages)}
      {"ok", 12, 1}

      iex> alias ExQuality.{Report, Stage}
      iex> report = Report.build([Stage.skipped("Tests", "--skip test")], 12, profile: :loop)
      iex> {report.profile, report.scope}
      {"loop", "all"}
  """
  @spec build([Stage.result()], non_neg_integer(), keyword()) :: t()
  def build(results, duration_ms, config \\ []) do
    coverage = coverage(results, config)

    %{
      version: version(),
      status: overall_status(results),
      duration_ms: duration_ms,
      profile: config |> Keyword.get(:profile) |> maybe_string(),
      scope: coverage.scope,
      base_ref: coverage.base_ref,
      stages: Enum.map(results, &stage/1)
    }
  end

  # The test stage is the only stage that narrows scope, so its own account of
  # what it ran is the root's. A run where it did not run at all reports what was
  # asked for, which is the closest thing to true available.
  defp coverage(results, config) do
    meta =
      results
      |> Enum.find(%{}, &(&1.name == "Tests"))
      |> Map.get(:meta, %{})

    %{
      scope: Map.get(meta, :scope) || Scope.describe(Scope.from_config(config)),
      base_ref: Map.get(meta, :base_ref)
    }
  end

  defp maybe_string(nil), do: nil
  defp maybe_string(value), do: to_string(value)

  @doc """
  Encodes a report as pretty-printed JSON, newline terminated.

      iex> ExQuality.Report.encode!(%{status: "ok"})
      "{\\n  \\"status\\": \\"ok\\"\\n}\\n"
  """
  @spec encode!(map()) :: String.t()
  def encode!(report), do: Jason.encode!(report, pretty: true) <> "\n"

  defp version do
    case Application.spec(:ex_quality, :vsn) do
      nil -> "unknown"
      vsn -> to_string(vsn)
    end
  end

  # A run is an error if any stage failed. A skipped stage is neither: it is
  # reported as itself so the caller can decide whether the gap matters.
  defp overall_status(results) do
    if Enum.any?(results, &(&1.status == :error)), do: "error", else: "ok"
  end

  defp stage(result) do
    findings = Stage.findings(result)

    %{
      name: result.name,
      status: to_string(result.status),
      summary: result.summary,
      skip_kind: skip_kind(result),
      duration_ms: result.duration_ms,
      stats: stats(result.stats),
      findings: Enum.map(findings, &finding/1)
    }
    |> Map.merge(Map.get(result, :meta, %{}))
    |> put_output(result, findings)
  end

  # `:project` is the default for a skipped stage that carries no kind - a
  # custom stage that has not opted in - because an unlabelled skip should
  # fail to attest as a standing gap rather than pass as a narrowing.
  defp skip_kind(%{status: :skipped} = result) do
    result |> Map.get(:skip_kind, :project) |> to_string()
  end

  defp skip_kind(_result), do: nil

  # Same rule as the human renderer: findings when the stage parsed its output,
  # the tool's output verbatim when it did not. Output is carried only for a
  # failure, because a passing stage's chatter is not something to act on.
  defp put_output(stage, %{status: :error, output: output}, []) when output != "" do
    Map.put(stage, :output, output)
  end

  defp put_output(stage, _result, _findings), do: stage

  # Per-app numbers are lists of pairs so their order is stable for rendering;
  # JSON has objects for that, so they become one.
  defp stats(stats) do
    Map.new(stats, fn
      {key, [{name, _value} | _rest] = pairs} when is_binary(name) -> {key, Map.new(pairs)}
      {key, value} -> {key, value}
    end)
  end

  defp finding(%Finding{} = finding) do
    %{
      file: finding.file,
      line: finding.line,
      column: finding.column,
      app: finding.app && to_string(finding.app),
      severity: to_string(finding.severity),
      check: finding.check,
      message: finding.message
    }
  end
end
