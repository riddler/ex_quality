defmodule Quality.Stages.Gettext do
  @moduledoc """
  Checks translation completeness using gettext.

  Runs `mix gettext.extract --merge` then scans .po files for:
  - Missing translations (empty msgstr)
  - Fuzzy translations (marked with #, fuzzy)

  Provides actionable output with file:line and msgid for each issue.

  This stage is automatically enabled only if `:gettext` is in deps.
  """

  @doc """
  Runs the gettext stage.
  """
  @spec run(keyword()) :: Quality.Stage.result()
  def run(_config) do
    start_time = System.monotonic_time(:millisecond)

    # Run extraction to ensure .po files are up to date
    {_output, extract_exit} =
      System.cmd("mix", ["gettext.extract", "--merge"],
        env: [{"MIX_ENV", "dev"}],
        stderr_to_stdout: true
      )

    duration_ms = System.monotonic_time(:millisecond) - start_time

    if extract_exit != 0 do
      %{
        name: "Gettext",
        status: :error,
        output: "Gettext extraction failed",
        stats: %{},
        summary: "Extraction failed",
        duration_ms: duration_ms
      }
    else
      check_translations(duration_ms)
    end
  end

  defp check_translations(duration_ms) do
    po_files = find_po_files()

    missing = collect_missing_translations(po_files)
    fuzzy = collect_fuzzy_translations(po_files)

    total_missing = count_items(missing)
    total_fuzzy = count_items(fuzzy)

    cond do
      total_missing > 0 and total_fuzzy > 0 ->
        missing_output = format_errors("missing", missing)
        fuzzy_output = format_errors("fuzzy", fuzzy)
        output = "#{missing_output}\n\n#{fuzzy_output}"

        %{
          name: "Gettext",
          status: :error,
          output: output,
          stats: %{missing_translations: total_missing, fuzzy_translations: total_fuzzy},
          summary: "#{total_missing} missing, #{total_fuzzy} fuzzy translation(s)",
          duration_ms: duration_ms
        }

      total_missing > 0 ->
        %{
          name: "Gettext",
          status: :error,
          output: format_errors("missing", missing),
          stats: %{missing_translations: total_missing},
          summary: "#{total_missing} missing translation(s)",
          duration_ms: duration_ms
        }

      total_fuzzy > 0 ->
        %{
          name: "Gettext",
          status: :error,
          output: format_errors("fuzzy", fuzzy),
          stats: %{fuzzy_translations: total_fuzzy},
          summary: "#{total_fuzzy} fuzzy translation(s)",
          duration_ms: duration_ms
        }

      true ->
        %{
          name: "Gettext",
          status: :ok,
          output: "",
          stats: %{},
          summary: "All translations complete",
          duration_ms: duration_ms
        }
    end
  end

  defp find_po_files do
    case System.cmd("find", ["priv/gettext", "-name", "*.po"], stderr_to_stdout: true) do
      {output, 0} ->
        output
        |> String.trim()
        |> String.split("\n")
        |> Enum.reject(&(&1 == ""))
        |> Enum.reject(&String.contains?(&1, "/en/"))
        |> Enum.reject(&String.contains?(&1, "errors.po"))

      _ ->
        []
    end
  end

  defp collect_missing_translations(po_files) do
    po_files
    |> Enum.map(fn file ->
      {file, find_untranslated_strings_with_lines(file)}
    end)
    |> Enum.reject(fn {_file, items} -> items == [] end)
  end

  defp collect_fuzzy_translations(po_files) do
    po_files
    |> Enum.map(fn file ->
      {file, find_fuzzy_strings_with_lines(file)}
    end)
    |> Enum.reject(fn {_file, items} -> items == [] end)
  end

  defp find_untranslated_strings_with_lines(po_file) do
    case File.read(po_file) do
      {:ok, content} ->
        content
        |> String.split("\n")
        |> parse_po_for_untranslated_with_lines()
        |> Enum.reject(fn {_line, msgid} -> msgid == "" end)

      {:error, _reason} ->
        []
    end
  end

  defp parse_po_for_untranslated_with_lines(lines) do
    lines
    |> Enum.with_index()
    |> Enum.reduce([], fn {line, index}, acc ->
      if String.match?(line, ~r/^msgstr ""$/) do
        case find_msgid_before_line_with_number(lines, index) do
          {msgid, line_num} when msgid != "" ->
            [{line_num + 1, msgid} | acc]

          _ ->
            acc
        end
      else
        acc
      end
    end)
    |> Enum.reverse()
  end

  defp find_msgid_before_line_with_number(lines, msgstr_index) do
    lines
    |> Enum.take(msgstr_index)
    |> Enum.with_index()
    |> Enum.reverse()
    |> Enum.find(fn {line, _idx} -> String.starts_with?(line, "msgid ") end)
    |> case do
      nil ->
        {"", 0}

      {msgid_line, line_num} ->
        msgid =
          msgid_line
          |> String.replace(~r/^msgid "/, "")
          |> String.replace(~r/"$/, "")

        {msgid, line_num}
    end
  end

  defp find_fuzzy_strings_with_lines(po_file) do
    case File.read(po_file) do
      {:ok, content} ->
        content
        |> String.split("\n")
        |> parse_po_for_fuzzy_with_lines()
        |> Enum.reject(fn {_line, msgid} -> msgid == "" end)

      {:error, _reason} ->
        []
    end
  end

  defp parse_po_for_fuzzy_with_lines(lines) do
    lines
    |> Enum.with_index()
    |> Enum.reduce([], fn {line, index}, acc ->
      if String.match?(line, ~r/^#,.*\bfuzzy\b/) do
        case find_msgid_after_line_with_number(lines, index) do
          {msgid, line_num} when msgid != "" ->
            [{line_num + 1, msgid} | acc]

          _ ->
            acc
        end
      else
        acc
      end
    end)
    |> Enum.reverse()
  end

  defp find_msgid_after_line_with_number(lines, fuzzy_index) do
    lines
    |> Enum.drop(fuzzy_index + 1)
    |> Enum.with_index(fuzzy_index + 1)
    |> Enum.find(fn {line, _idx} -> String.starts_with?(line, "msgid ") end)
    |> case do
      nil ->
        {"", 0}

      {msgid_line, line_num} ->
        msgid =
          msgid_line
          |> String.replace(~r/^msgid "/, "")
          |> String.replace(~r/"$/, "")

        {msgid, line_num}
    end
  end

  defp count_items(file_items) do
    Enum.sum(Enum.map(file_items, fn {_file, items} -> length(items) end))
  end

  defp format_errors(type, file_items) do
    header = "#{String.capitalize(type)} translations:\n"

    file_details =
      Enum.map(file_items, fn {file, items} ->
        display_file = String.replace_leading(file, "./", "")

        item_details =
          items
          |> Enum.take(5)
          |> Enum.map(fn {line, msgid} ->
            truncated_msgid =
              if String.length(msgid) > 60 do
                String.slice(msgid, 0, 57) <> "..."
              else
                msgid
              end

            "  #{display_file}:#{line} - \"#{truncated_msgid}\""
          end)
          |> Enum.join("\n")

        remaining = length(items) - 5
        remaining_msg = if remaining > 0, do: "\n  ... and #{remaining} more", else: ""

        "#{display_file} (#{length(items)} #{type}):\n#{item_details}#{remaining_msg}"
      end)
      |> Enum.join("\n\n")

    "#{header}#{file_details}"
  end
end
