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

  ## Metadata

  A stage may also return `meta`, a map of extra report fields describing *what
  the stage did* rather than what it found. The test stage uses it to say how
  much of the suite it ran, because `"status": "ok"` over three test files and
  `"status": "ok"` over the whole suite are different claims and a consumer has
  to be able to tell them apart. Keys are merged into the stage's object in the
  JSON report.

  ## Skipped stages

  A stage that was considered and not run returns a `:skipped` result carrying
  the reason in `summary`, built with `skipped/3`. A run that says nothing about
  a stage is indistinguishable from a run where the stage had nothing to say,
  so silence is never an option.

  A skip has a kind as well as a reason, because the two kinds mean opposite
  things to whoever reads the run afterwards. `:run` means the caller asked for
  a narrower run - `--quick`, a profile, `--until-first-failure` - and a full
  `mix quality` closes the gap. `:project` means the project does not check
  this at all - the tool is not installed, the stage is disabled in
  `.quality.exs` - and a fuller run cannot close it. The kind is structural
  rather than read out of the reason's wording, so a consumer such as
  `mix quality.verify` never has to substring-match prose that a patch release
  is free to rephrase.
  """

  alias ExQuality.Finding

  @typedoc """
  Whether a stage reads the build or writes to it.

  The analysis phase runs its stages concurrently, which is only safe while
  every one of them is a reader. A stage that recompiles the project or
  rewrites files under `_build` invalidates the beams the others are part-way
  through reading, and the reader that notices reports a failure that has
  nothing to do with the code. Writers are run on their own, before the
  readers, for the same reason compilation is a serialized gate.

  A stage that does not say is a `:reader`.
  """
  @type kind :: :reader | :writer

  @typedoc """
  What a `:skipped` result means to whoever reads the run afterwards.

  `:run` names this run: the caller asked for a narrower one, and a full
  `mix quality` closes the gap. `:project` names the project: it does not
  check this at all, and a fuller run cannot close it.
  """
  @type skip_kind :: :run | :project

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
          optional(:files_needing_format) => non_neg_integer(),
          optional(:missing_translations) => non_neg_integer(),
          optional(:fuzzy_translations) => non_neg_integer(),
          optional(:file_count) => non_neg_integer(),
          optional(:finding_count) => non_neg_integer(),
          optional(:blocking_count) => non_neg_integer(),
          optional(:informational_count) => non_neg_integer(),
          optional(:blocking_by_confidence) => [{String.t(), non_neg_integer()}],
          # A custom stage carries its tool's own stats, string-keyed: the names
          # come from a config file, and atomising arbitrary ones is unbounded.
          optional(String.t()) => term()
        }

  @type result :: %{
          required(:name) => String.t(),
          required(:status) => :ok | :error | :skipped,
          required(:output) => String.t(),
          required(:stats) => stats(),
          required(:summary) => String.t(),
          required(:duration_ms) => non_neg_integer(),
          optional(:skip_kind) => skip_kind(),
          optional(:findings) => [Finding.t()],
          optional(:meta) => %{atom() => term()}
        }

  @doc """
  Returns a result's findings, or an empty list when the stage reported none.

      iex> ExQuality.Stage.findings(%{name: "Credo"})
      []
  """
  @spec findings(map()) :: [Finding.t()]
  def findings(result), do: Map.get(result, :findings, [])

  @doc """
  Returns whether a stage module reads the build or writes to it.

  A module says so by exporting `stage_kind/1`, which is given the run's
  config because a stage can be a writer only in some configurations. A module
  that does not export it is a `:reader`, so classifying a stage is one
  function on the stage that has something to declare rather than a line on
  every stage that does not.

      iex> ExQuality.Stage.kind(ExQuality.Stages.Credo, [])
      :reader

      iex> ExQuality.Stage.kind(ExQuality.Stages.Gettext, gettext: [extract: true])
      :writer
  """
  @spec kind(module(), keyword()) :: kind()
  def kind(module, config) do
    if Code.ensure_loaded?(module) and function_exported?(module, :stage_kind, 1) do
      module.stage_kind(config)
    else
      :reader
    end
  end

  @doc """
  Builds a `:skipped` result for a stage that was considered and not run.

  The reason is carried in `summary` so renderers can say why the stage did
  not run rather than leaving a gap in the output. The kind says which of the
  two things the skip means - see `t:skip_kind/0`.

  The default kind is `:project`, because that is the conservative direction:
  an unlabelled skip fails to attest as a standing gap rather than passing as
  a narrowing nobody declared. Every built-in call site passes the kind; a
  custom stage that skips itself should too.

      iex> ExQuality.Stage.skipped("Dialyzer", "--quick", :run)
      %{
        name: "Dialyzer",
        status: :skipped,
        output: "",
        stats: %{},
        summary: "--quick",
        duration_ms: 0,
        skip_kind: :run
      }

      iex> ExQuality.Stage.skipped("Sobelow", ":sobelow not installed").skip_kind
      :project
  """
  @spec skipped(String.t(), String.t(), skip_kind()) :: result()
  def skipped(name, reason, kind \\ :project) do
    %{
      name: name,
      status: :skipped,
      output: "",
      stats: %{},
      summary: reason,
      duration_ms: 0,
      skip_kind: kind
    }
  end
end
