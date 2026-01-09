defmodule Quality.Stages.Credo do
  @moduledoc """
  Runs Credo static analysis on the codebase.

  Executes `mix credo --strict` (configurable) with MIX_ENV=dev.
  Parses issue count and categories, extracting file:line references
  for actionable feedback.

  Note: Credo does not support auto-fix. All issues must be manually resolved.
  """

  @doc """
  Runs the credo stage.

  ## Config options

  - `strict` - Use `--strict` mode (default: true)
  - `all` - Use `--all` flag to check all files (default: false)
  """
  @spec run(keyword()) :: Quality.Stage.result()
  def run(config) do
    start_time = System.monotonic_time(:millisecond)

    credo_config = Keyword.get(config, :credo, [])
    strict = Keyword.get(credo_config, :strict, true)
    all = Keyword.get(credo_config, :all, false)

    args = build_args(strict, all)

    {output, exit_code} =
      System.cmd("mix", args,
        env: [{"MIX_ENV", "dev"}],
        stderr_to_stdout: true
      )

    duration_ms = System.monotonic_time(:millisecond) - start_time
    issue_count = parse_issue_count(output)

    case exit_code do
      0 ->
        %{
          name: "Credo",
          status: :ok,
          output: output,
          stats: %{issue_count: 0},
          summary: "No issues",
          duration_ms: duration_ms
        }

      _error ->
        %{
          name: "Credo",
          status: :error,
          output: output,
          stats: %{issue_count: issue_count},
          summary: format_summary(issue_count, output),
          duration_ms: duration_ms
        }
    end
  end

  defp build_args(strict, all) do
    args = ["credo"]

    args =
      if strict do
        args ++ ["--strict"]
      else
        args
      end

    if all do
      args ++ ["--all"]
    else
      args
    end
  end

  defp parse_issue_count(output) do
    # Try to parse from the summary line like:
    # "51 mods/funs, found 1 refactoring opportunity, 2 code readability issues, 2 software design suggestions."
    # We need to sum up all the numbers

    # Look for lines that contain issue counts
    refactor = parse_count_from_summary(output, ~r/(\d+)\s+refactoring/)
    readability = parse_count_from_summary(output, ~r/(\d+)\s+code readability/)
    design = parse_count_from_summary(output, ~r/(\d+)\s+software design/)
    warning = parse_count_from_summary(output, ~r/(\d+)\s+warning/)
    consistency = parse_count_from_summary(output, ~r/(\d+)\s+consistency/)

    total = refactor + readability + design + warning + consistency

    if total > 0 do
      total
    else
      # Fallback: Count lines with issue markers like "[W]" or "[R]" or "[C]" or "[F]" or "[D]"
      # Format: "┃ [X] ↗ Message"
      output
      |> String.split("\n")
      |> Enum.count(&String.match?(&1, ~r/\[[WCRFD]\]/))
    end
  end

  defp parse_count_from_summary(output, regex) do
    case Regex.run(regex, output) do
      [_, count] -> String.to_integer(count)
      _ -> 0
    end
  end

  defp format_summary(issue_count, output) do
    # Try to extract issue breakdown (consistency, design, readability, refactor, warning)
    categories = parse_categories(output)

    if categories == [] do
      case issue_count do
        1 -> "1 issue found"
        n -> "#{n} issues found"
      end
    else
      # Format as "X issues (2 design, 3 readability)"
      category_str = Enum.join(categories, ", ")
      "#{issue_count} issue(s) (#{category_str})"
    end
  end

  defp parse_categories(output) do
    # Parse from summary line like:
    # "51 mods/funs, found 1 refactoring opportunity, 2 code readability issues, 2 software design suggestions."

    patterns = [
      {~r/(\d+)\s+refactoring/, "refactoring"},
      {~r/(\d+)\s+code readability/, "readability"},
      {~r/(\d+)\s+software design/, "design"},
      {~r/(\d+)\s+warning/, "warning"},
      {~r/(\d+)\s+consistency/, "consistency"}
    ]

    Enum.flat_map(patterns, fn {regex, name} ->
      case Regex.run(regex, output) do
        [_, count] ->
          count_int = String.to_integer(count)
          if count_int > 0, do: ["#{count_int} #{name}"], else: []

        _ ->
          []
      end
    end)
  end
end
