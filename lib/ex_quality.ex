defmodule ExQuality do
  @moduledoc """
  ExQuality - A parallel code quality checker for Elixir projects.

  Automatically fixes formatting issues, then runs all analysis stages
  in parallel with streaming output and actionable feedback.

  ## Quick Start

      # Everything: the gate, before a commit and in CI
      mix quality

      # Quick mode: skips dialyzer and coverage enforcement
      mix quality --quick

      # The inner loop: only the tests covering what changed
      mix quality --test-scope changed

  ## Features

  - **Auto-fix first** - Automatically fixes formatting before analysis
  - **Parallel execution** - Maximizes CPU utilization
  - **Streaming output** - See results as each stage completes
  - **Auto-detection** - Enables stages based on installed dependencies
  - **Actionable feedback** - Shows file:line references for issues
  - **Scoped runs** - Narrows *how much code* a run covers, not just which
    checks it runs, which is what makes a between-edits loop affordable. See
    `ExQuality.Scope`
  - **Configurable** - Customize via `.quality.exs`, including named profiles
  - **LLM-friendly** - Includes `usage-rules.md` for AI assistants

  ## Supported Quality Checks

  - Format (mix format)
  - Compilation (dev + test environments)
  - Credo (static analysis)
  - Dialyzer (type checking)
  - Doctor (documentation coverage)
  - Gettext (translation completeness)
  - Sobelow (security analysis)
  - Dependencies (unused deps and security audit)
  - Tests (with optional coverage via excoveralls)

  A project's own checks run as stages of the same run, declared under `custom:`
  in `.quality.exs`. See `ExQuality.Custom`.

  See `Mix.Tasks.Quality` for detailed usage information.
  """

  @version Mix.Project.config()[:version]

  @doc """
  Returns the version of the ExQuality package.
  """
  @spec version() :: String.t()
  def version, do: @version
end
