defmodule ExQuality.Stage do
  @moduledoc """
  Type definitions for quality check stage results.

  Each stage returns a result map with standardized fields for
  status, output, stats, and timing information.
  """

  @type stats :: %{
          optional(:test_count) => non_neg_integer(),
          optional(:passed_count) => non_neg_integer(),
          optional(:failed_count) => non_neg_integer(),
          optional(:coverage) => float(),
          optional(:warning_count) => non_neg_integer(),
          optional(:issue_count) => non_neg_integer(),
          optional(:files_formatted) => non_neg_integer()
        }

  @type result :: %{
          name: String.t(),
          status: :ok | :error | :skipped,
          output: String.t(),
          stats: stats(),
          summary: String.t(),
          duration_ms: non_neg_integer()
        }
end
