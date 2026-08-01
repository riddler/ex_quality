defmodule ExQuality.OutputCollector do
  @moduledoc """
  Collects command output without streaming to console.

  Implements the Collectable protocol for use with System.cmd/3's
  :into option. Stores all output in memory for later retrieval.

  ## Example

      collector = ExQuality.OutputCollector.new()
      {_output, _exit_code} = System.cmd("mix", ["compile"], into: collector)
      output = ExQuality.OutputCollector.get_output(collector)

  ## Watching output as it arrives

  A collector can also be given an `:on_line` handler, called with each
  complete line as the command produces it:

      collector = ExQuality.OutputCollector.new(on_line: &IO.puts/1)

  A stage whose tool can stall for minutes needs this to report progress while
  it happens; the collected output is only available once the command has
  exited. Lines are reassembled here because a chunk arrives at whatever
  boundary the port gives it, which is rarely a line.
  """

  defstruct [:pid]

  @type t :: %__MODULE__{pid: pid()}

  @doc """
  Creates a new output collector.

  ## Options

  - `:on_line` - a one-argument function called with each complete line of
    output as it arrives, without its trailing newline.
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    on_line = Keyword.get(opts, :on_line)

    {:ok, pid} = Agent.start_link(fn -> %{chunks: [], buffer: "", on_line: on_line} end)

    %__MODULE__{pid: pid}
  end

  @doc """
  Retrieves the collected output as a binary string.
  """
  @spec get_output(t()) :: String.t()
  def get_output(%__MODULE__{pid: pid}) do
    chunks = Agent.get(pid, & &1.chunks)
    Agent.stop(pid)

    chunks
    |> Enum.reverse()
    |> IO.iodata_to_binary()
  end

  @doc false
  # Kept out of the Collectable implementation so the line reassembly is
  # testable on its own.
  @spec collect(pid(), iodata()) :: :ok
  def collect(pid, chunk) do
    Agent.update(pid, fn state ->
      state = %{state | chunks: [chunk | state.chunks]}

      case state.on_line do
        nil ->
          state

        on_line ->
          %{state | buffer: emit_lines(state.buffer <> IO.iodata_to_binary(chunk), on_line)}
      end
    end)
  end

  # The last element is whatever came after the final newline: a partial line,
  # or "" when the chunk ended on one. Either way it waits for the next chunk.
  defp emit_lines(text, on_line) do
    [buffer | complete] = text |> String.split("\n") |> Enum.reverse()

    complete
    |> Enum.reverse()
    |> Enum.each(on_line)

    buffer
  end

  defimpl Collectable do
    def into(%ExQuality.OutputCollector{pid: pid}) do
      collector_fun = fn
        _acc, {:cont, chunk} ->
          ExQuality.OutputCollector.collect(pid, chunk)
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
