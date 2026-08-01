defmodule ExQuality.Json do
  @moduledoc """
  Reads a JSON document out of a command's output.

  A tool asked for `--format json` writes JSON, but it is rarely the only
  thing on the stream: `mix` compiles the project first, and anything it or
  the tool prints lands ahead of the report. So the document is looked for
  rather than assumed.

  Three candidates are tried, in order: the whole output, each line that opens
  an object on its own (a compact document, as `mix deps.audit` writes), and
  the rest of the output from each such line (a pretty-printed one, as
  `mix credo` writes). Only lines opening in column one are considered, so a
  large document's nested objects are not each tried as a document of their
  own.

  Returns `:error` rather than raising, because a tool that printed no JSON is
  something the caller has to report, not something it can fix.
  """

  @doc """
  Decodes the JSON document in `output`, or returns `:error`.

      iex> ExQuality.Json.decode(~s|Compiling 3 files\\n{"issues": []}|)
      {:ok, %{"issues" => []}}

      iex> ExQuality.Json.decode("** (Mix) Could not invoke task")
      :error
  """
  @spec decode(String.t()) :: {:ok, term()} | :error
  def decode(output) do
    output
    |> candidates()
    |> Enum.find_value(:error, &try_decode/1)
  end

  defp candidates(output) do
    lines = String.split(output, "\n")

    openings =
      for {line, index} <- Enum.with_index(lines), String.starts_with?(line, "{"), do: index

    [output | Enum.flat_map(openings, &[Enum.at(lines, &1), suffix(lines, &1)])]
  end

  defp suffix(lines, index) do
    lines |> Enum.drop(index) |> Enum.join("\n")
  end

  defp try_decode(candidate) do
    case Jason.decode(candidate) do
      {:ok, decoded} -> {:ok, decoded}
      {:error, _reason} -> nil
    end
  end
end
