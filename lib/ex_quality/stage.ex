defmodule ExQuality.Stage do
  @moduledoc """
  Type definitions for quality check stage results.

  Each stage returns a result map with standardized fields for
  status, output, stats, and timing information.

  ## Findings

  A stage may also return `findings`, a list of `ExQuality.Finding` structs
  parsed from its tool's output. Findings are optional: a stage that has no
  parser, or whose output did not parse this run, simply omits the key.

  Renderers follow one rule:

  1. If `findings` is non-empty, render the findings.
  2. Otherwise, print `output` verbatim. Unparseable output is never hidden.

  ## Skipped stages

  A stage that was considered and not run returns a `:skipped` result carrying
  the reason in `summary`, built with `skipped/2`. A run that says nothing about
  a stage is indistinguishable from a run where the stage had nothing to say,
  so silence is never an option.
  """

  alias ExQuality.Finding

  @type stats :: %{
          optional(:test_count) => non_neg_integer(),
          optional(:passed_count) => non_neg_integer(),
          optional(:failed_count) => non_neg_integer(),
          optional(:failures_by_app) => [{String.t(), non_neg_integer()}],
          optional(:coverage) => float(),
          optional(:coverage_by_app) => [{String.t(), float()}],
          optional(:coverage_required) => number(),
          optional(:warning_count) => non_neg_integer(),
          optional(:plt_built) => boolean(),
          optional(:issue_count) => non_neg_integer(),
          optional(:unused_deps) => non_neg_integer(),
          optional(:vulnerabilities) => non_neg_integer(),
          optional(:vulnerabilities_by_severity) => [{String.t(), non_neg_integer()}],
          optional(:files_formatted) => non_neg_integer(),
          optional(:finding_count) => non_neg_integer(),
          optional(:blocking_count) => non_neg_integer(),
          optional(:informational_count) => non_neg_integer(),
          optional(:blocking_by_confidence) => [{String.t(), non_neg_integer()}]
        }

  @type result :: %{
          required(:name) => String.t(),
          required(:status) => :ok | :error | :skipped,
          required(:output) => String.t(),
          required(:stats) => stats(),
          required(:summary) => String.t(),
          required(:duration_ms) => non_neg_integer(),
          optional(:findings) => [Finding.t()]
        }

  @doc """
  Returns a result's findings, or an empty list when the stage reported none.

      iex> ExQuality.Stage.findings(%{name: "Credo"})
      []
  """
  @spec findings(map()) :: [Finding.t()]
  def findings(result), do: Map.get(result, :findings, [])

  @doc """
  Builds a `:skipped` result for a stage that was considered and not run.

  The reason is carried in `summary` so renderers can say why the stage did
  not run rather than leaving a gap in the output.

      iex> ExQuality.Stage.skipped("Dialyzer", "--quick")
      %{
        name: "Dialyzer",
        status: :skipped,
        output: "",
        stats: %{},
        summary: "--quick",
        duration_ms: 0
      }
  """
  @spec skipped(String.t(), String.t()) :: result()
  def skipped(name, reason) do
    %{
      name: name,
      status: :skipped,
      output: "",
      stats: %{},
      summary: reason,
      duration_ms: 0
    }
  end
end
