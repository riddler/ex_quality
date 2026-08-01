defmodule ExQuality.Printer do
  @moduledoc """
  Serializes output from parallel stages to prevent interleaving.

  Each stage calls `print_result/1` when complete, which acquires
  a lock and prints the entire summary atomically. This ensures
  that if multiple stages complete simultaneously, their output
  won't be interleaved.

  ## Usage

      {:ok, _pid} = ExQuality.Printer.start_link()

      # From multiple parallel tasks:
      ExQuality.Printer.print_result(result)

      ExQuality.Printer.stop()
  """

  use Agent

  @doc """
  Starts the printer agent.
  """
  @spec start_link(keyword()) :: Agent.on_start()
  def start_link(opts \\ []) do
    Agent.start_link(fn -> :ok end, Keyword.put(opts, :name, __MODULE__))
  end

  @doc """
  Stops the printer agent.
  """
  @spec stop() :: :ok
  def stop do
    Agent.stop(__MODULE__)
  end

  @doc """
  Prints a stage result atomically.

  Blocks until any concurrent print operation completes,
  then prints the full result without interruption.
  """
  @spec print_result(ExQuality.Stage.result()) :: :ok
  def print_result(result) do
    Agent.get_and_update(__MODULE__, fn state ->
      # Print while holding the agent lock
      do_print_result(result)
      {:ok, state}
    end)
  end

  @doc """
  Prints a simple message atomically.

  A stage reporting progress may also be run on its own, outside a parallel
  run, so a message printed with no printer started goes straight to the shell
  rather than failing: there is nothing to serialize against.
  """
  @spec print_message(String.t()) :: :ok
  def print_message(message) do
    case Process.whereis(__MODULE__) do
      nil ->
        Mix.shell().info(message)

      _pid ->
        Agent.get_and_update(__MODULE__, fn state ->
          Mix.shell().info(message)
          {:ok, state}
        end)
    end
  end

  defp do_print_result(%{status: :ok} = result) do
    Mix.shell().info(
      "✓ #{result.name}: #{result.summary} (#{format_duration(result.duration_ms)})"
    )
  end

  defp do_print_result(%{status: :error} = result) do
    Mix.shell().error(
      "✗ #{result.name}: #{result.summary} (#{format_duration(result.duration_ms)})"
    )
  end

  defp do_print_result(%{status: :skipped} = result) do
    Mix.shell().info("○ #{result.name}: skipped#{skip_reason(result)}")
  end

  defp skip_reason(%{summary: reason}) when is_binary(reason) and reason != "", do: " (#{reason})"
  defp skip_reason(_result), do: ""

  defp format_duration(ms) when ms < 1000, do: "#{ms}ms"
  defp format_duration(ms), do: "#{Float.round(ms / 1000, 1)}s"
end
