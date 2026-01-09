defmodule Quality.OutputCollector do
  @moduledoc """
  Collects command output without streaming to console.

  Implements the Collectable protocol for use with System.cmd/3's
  :into option. Stores all output in memory for later retrieval.

  ## Example

      collector = Quality.OutputCollector.new()
      {_output, _exit_code} = System.cmd("mix", ["compile"], into: collector)
      output = Quality.OutputCollector.get_output(collector)
  """

  defstruct [:pid]

  @type t :: %__MODULE__{pid: pid()}

  @doc """
  Creates a new output collector.
  """
  @spec new() :: t()
  def new do
    {:ok, pid} = Agent.start_link(fn -> [] end)
    %__MODULE__{pid: pid}
  end

  @doc """
  Retrieves the collected output as a binary string.
  """
  @spec get_output(t()) :: String.t()
  def get_output(%__MODULE__{pid: pid}) do
    chunks = Agent.get(pid, & &1)
    Agent.stop(pid)

    chunks
    |> Enum.reverse()
    |> IO.iodata_to_binary()
  end

  defimpl Collectable do
    def into(%Quality.OutputCollector{pid: pid}) do
      collector_fun = fn
        _acc, {:cont, chunk} ->
          Agent.update(pid, fn chunks -> [chunk | chunks] end)
          nil

        _acc, :done ->
          nil

        _acc, :halt ->
          nil
      end

      {nil, collector_fun}
    end
  end
end
