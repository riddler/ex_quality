defmodule ExQuality.Aliases do
  @moduledoc """
  Detects when a project's Mix aliases shadow a task a stage shells out to.

  Mix resolves aliases before tasks, so `mix sobelow` in a project whose
  `mix.exs` says

      aliases: [sobelow: ["cmd --app web mix sobelow --config"]]

  runs the alias and ignores every switch a stage passed. The stage then
  measures something other than what it asked for, and the failure is quiet:
  a report that was never written, or a suite run twice and counted twice.

  The task names ExQuality shells out to are exactly the ones projects most
  like to alias - `credo`, `dialyzer`, `format`, `sobelow`, `deps.unlock`,
  `test.coverage` - so a stage whose parsing depends on its exact invocation
  asks here first, and refuses to run rather than reporting a number about a
  command it did not issue.

  Detection, not bypass: silently ignoring a project's alias is its own
  surprise, and naming it gives the reader the choice.

  ## `test` is deliberately not on the list

  A `test:` alias (`["ecto.create --quiet", "ecto.migrate", "test"]`) is
  near-universal and running it is correct - it does the setup the suite needs.
  `test.coverage` is different: it is pure aggregation, and an alias on it runs
  the suite a second time before aggregating.
  """

  alias ExQuality.Stage

  @doc """
  Returns true when the project defines a Mix alias with this task's name.

  Safe to call outside a Mix project, where there are no aliases to shadow
  anything.

      iex> ExQuality.Aliases.shadowing?("no.such.task")
      false
  """
  @spec shadowing?(String.t() | atom()) :: boolean()
  def shadowing?(task) do
    Keyword.has_key?(aliases(), key(task))
  end

  @doc """
  Returns an `:error` result for a stage that will not run because its task is
  aliased, naming the alias and what to do about it.

  The suggested rename is `<task>.all`, which is a name Mix will not resolve to
  the real task and which reads as "the project's own wrapper".

      iex> result = ExQuality.Aliases.shadowed("Sobelow", "sobelow")
      iex> result.summary
      "mix sobelow is aliased in mix.exs"
  """
  @spec shadowed(String.t(), String.t()) :: Stage.result()
  def shadowed(name, task) do
    %{
      name: name,
      status: :error,
      output: """
      ExQuality runs `mix #{task}` and reads what it prints, but this project
      defines a Mix alias named `#{task}` in mix.exs. Mix resolves aliases
      before tasks, so the alias runs instead and the switches this stage
      passes are ignored.

      Rename the alias - `#{task}.all` is the usual choice - and point your own
      scripts at the new name.
      """,
      findings: [],
      stats: %{},
      summary: "mix #{task} is aliased in mix.exs",
      duration_ms: 0
    }
  end

  defp aliases do
    case Mix.Project.get() do
      nil -> []
      _module -> Mix.Project.config()[:aliases] || []
    end
  end

  defp key(task) when is_atom(task), do: task
  defp key(task) when is_binary(task), do: String.to_atom(task)
end
