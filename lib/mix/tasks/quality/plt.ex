defmodule Mix.Tasks.Quality.Plt do
  @shortdoc "Builds the Dialyzer PLT so a quality run does not have to"

  @moduledoc """
  Builds the Dialyzer PLT ahead of a `mix quality` run.

  Dialyzer analyses against a PLT, a cache of every module it has already seen.
  Building one takes minutes; analysing against a warm one takes seconds. With
  no warm-up target, the first run on a cold checkout or a fresh CI container
  pays that cost inside a check whose only output is one line at the end, so
  the run looks hung.

  This task is that target. It is the same work `mix quality` would otherwise
  do, moved somewhere it can be cached:

      mix quality.plt

  In a container image or a CI job, run it in its own step, after
  `mix deps.get` and before any check, and cache `_build` and `~/.mix`
  (dialyxir keeps the core PLTs in the Mix home directory and the project's
  own under `_build`). The step is slow once and instant afterwards.

  Output is not summarised: unlike a check, the whole point of this task is the
  progress, so dialyxir's own output is passed through as it arrives.

  Requires `:dialyxir`. A project without it has no PLT to build.
  """

  use Mix.Task

  alias ExQuality.Tools

  @doc """
  Runs the PLT build.

  Fails the task if dialyxir is not installed, or if the build itself failed.
  """
  @spec run([String.t()]) :: :ok
  def run(_args) do
    unless Tools.available?(:dialyzer) do
      Mix.raise(
        "mix quality.plt needs :dialyxir, which this project does not depend on. " <>
          "Add it (or run mix quality.init) first."
      )
    end

    Mix.shell().info("Building the Dialyzer PLT. This is a one-time cost.\n")

    started = System.monotonic_time(:millisecond)
    exit_code = build_plt()
    duration_ms = System.monotonic_time(:millisecond) - started

    if exit_code != 0 do
      Mix.raise("PLT build failed (exit status #{exit_code})")
    end

    Mix.shell().info("\n✓ PLT ready (#{format_duration(duration_ms)})")

    :ok
  end

  defp build_plt do
    {_stream, exit_code} =
      System.cmd("mix", ["dialyzer", "--plt"],
        env: [{"MIX_ENV", "dev"}],
        stderr_to_stdout: true,
        into: IO.stream(:stdio, :line)
      )

    exit_code
  end

  defp format_duration(ms) when ms < 1000, do: "#{ms}ms"
  defp format_duration(ms), do: "#{Float.round(ms / 1000, 1)}s"
end
