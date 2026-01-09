defmodule Quality do
  @moduledoc """
  Quality - A parallel code quality checker for Elixir projects.

  Automatically fixes formatting issues, then runs all analysis stages
  in parallel with streaming output and actionable feedback.

  ## Quick Start

      # Run all quality checks
      mix quality

      # Quick mode (skip slow checks like dialyzer)
      mix quality --quick

  ## Features

  - **Auto-fix first** - Automatically fixes formatting before analysis
  - **Parallel execution** - Maximizes CPU utilization
  - **Streaming output** - See results as each stage completes
  - **Auto-detection** - Enables stages based on installed dependencies
  - **Actionable feedback** - Shows file:line references for issues
  - **Configurable** - Customize via `.quality.exs`
  - **LLM-friendly** - Includes `usage-rules.md` for AI assistants

  ## Supported Quality Checks

  - Format (mix format)
  - Compilation (dev + test environments)
  - Credo (static analysis)
  - Dialyzer (type checking)
  - Doctor (documentation coverage)
  - Gettext (translation completeness)
  - Tests (with optional coverage via excoveralls)

  See `Mix.Tasks.Quality` for detailed usage information.
  """

  @version Mix.Project.config()[:version]

  @doc """
  Returns the version of the Quality package.
  """
  @spec version() :: String.t()
  def version, do: @version
end
