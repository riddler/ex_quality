defmodule ExQuality.Plt do
  @moduledoc """
  Recognises PLT work in dialyxir's output.

  The PLT is dialyxir's cache of everything it has already analysed. Building
  one takes minutes; analysing against a warm one takes seconds. The Dialyzer
  stage prints a single line when it finishes, so on a cold checkout or a fresh
  CI container that line arrives several minutes after the run appears to have
  stalled, with nothing to say the wait is a one-time cost.

  This module names the lines dialyxir prints while it builds, so the stage can
  say what is happening while it is happening (`build_watcher/1`) and report
  afterwards that the run paid for a build (`built?/1`).

  A PLT build is not a reason to distrust the analysis that follows it, so a
  run that built one still passes or fails on its warnings alone. It is only
  reported, because it explains a duration a reader would otherwise read as a
  hang, and because it is the thing `mix quality.plt` exists to move out of the
  run.
  """

  # dialyxir prints these from `Dialyxir.Plt` and `Mix.Tasks.Dialyzer` while it
  # builds. "Checking N modules in ..." is deliberately absent: it runs against
  # a warm PLT too, so it says nothing about whether this run paid to build one.
  @build_markers [
    ~r/^Creating .+\.plt$/,
    ~r/^Copying .+\.plt to .+\.plt$/,
    ~r/^Adding \d+ modules? to .+\.plt$/,
    ~r/^In an Umbrella child and no PLT found/
  ]

  @message "building PLT (this is a one-time cost)"

  @doc """
  The progress message for a build in flight.

      iex> ExQuality.Plt.message()
      "building PLT (this is a one-time cost)"
  """
  @spec message() :: String.t()
  def message, do: @message

  @doc """
  Whether a single line of dialyxir output says a PLT is being built.

      iex> ExQuality.Plt.build_line?("Adding 1042 modules to dialyxir_erlang-25.3.plt")
      true

      iex> ExQuality.Plt.build_line?("Checking 365 modules in dialyxir_erlang-25.3.plt")
      false
  """
  @spec build_line?(String.t()) :: boolean()
  def build_line?(line) do
    trimmed = String.trim(line)

    Enum.any?(@build_markers, &Regex.match?(&1, trimmed))
  end

  @doc """
  Whether a run's output shows that a PLT was built.

      iex> ExQuality.Plt.built?("Checking PLT...\\nPLT is up to date!")
      false
  """
  @spec built?(String.t()) :: boolean()
  def built?(output) do
    output
    |> String.split("\n")
    |> Enum.any?(&build_line?/1)
  end

  @doc """
  Returns a line handler that calls `fun` once, on the first build line it sees.

  Suitable as `ExQuality.OutputCollector`'s `:on_line` handler, which is what
  makes the announcement arrive while the build is running rather than after it.
  Later build lines are ignored: a build prints several, and a stage that
  announced each of them would report progress as noise.
  """
  @spec build_watcher((-> any())) :: (String.t() -> :ok)
  def build_watcher(fun) when is_function(fun, 0) do
    # One atomic rather than a process, so the watcher has nothing to clean up
    # and cannot outlive the command it is watching.
    fired = :atomics.new(1, signed: false)

    fn line ->
      if build_line?(line) and :atomics.compare_exchange(fired, 1, 0, 1) == :ok do
        fun.()
      end

      :ok
    end
  end
end
