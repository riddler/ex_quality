defmodule ExQuality.Stages.Credo do
  @moduledoc """
  Runs Credo static analysis on the codebase.

  Executes `mix credo --strict --format json` (strictness is configurable) with
  MIX_ENV=dev, and turns each issue into an `ExQuality.Finding`.

  JSON rather than the default output because credo's text format does not name
  the check that produced an issue, and because counting issues out of it meant
  five regexes against a summary line that a reader could not check. The count
  is now `length(issues)`, and `check` is the check module
  (`Credo.Check.Readability.ModuleDoc`) rather than its category.

  In an umbrella, each finding is tagged with the app its file belongs to, and
  the rendered output is grouped by app.

  Output that does not parse is never hidden: a run that printed no JSON
  document is reported with whatever credo did say, which is what a version too
  old to know `--format json` produces.

  Note: Credo does not support auto-fix. All issues must be manually resolved.
  """

  alias ExQuality.Aliases
  alias ExQuality.Finding
  alias ExQuality.Json
  alias ExQuality.Umbrella

  # A warning is credo's own word for "this is probably a bug". The rest are
  # style, so they are informational rather than something to act on now.
  @severities %{"warning" => :warning}

  # Most severe first, so the summary leads with the category a reader should
  # look at. A category credo grows later sorts after these, by name.
  @category_order ~w(warning refactor readability design consistency)

  @doc """
  Runs the credo stage.

  ## Config options

  - `strict` - Use `--strict` mode (default: true)
  - `all` - Use `--all` flag to check all files (default: false)
  """
  @spec run(keyword()) :: ExQuality.Stage.result()
  def run(config) do
    if Aliases.shadowing?("credo") do
      Aliases.shadowed("Credo", "credo")
    else
      check(config)
    end
  end

  defp check(config) do
    start_time = System.monotonic_time(:millisecond)

    credo_config = Keyword.get(config, :credo, [])
    strict = Keyword.get(credo_config, :strict, true)
    all = Keyword.get(credo_config, :all, false)

    {output, exit_code} =
      System.cmd("mix", build_args(strict, all),
        env: [{"MIX_ENV", "dev"}],
        stderr_to_stdout: true
      )

    duration_ms = System.monotonic_time(:millisecond) - start_time

    case Json.decode(output) do
      {:ok, %{"issues" => issues}} when is_list(issues) ->
        report(issues, output, exit_code, duration_ms)

      _no_report ->
        unparsed(output, exit_code, duration_ms)
    end
  end

  defp build_args(strict, all) do
    args = ["credo", "--format", "json"]
    args = if strict, do: args ++ ["--strict"], else: args

    if all, do: args ++ ["--all"], else: args
  end

  defp report([], output, 0, duration_ms) do
    %{
      name: "Credo",
      status: :ok,
      output: output,
      stats: %{issue_count: 0},
      summary: "No issues",
      duration_ms: duration_ms
    }
  end

  # Credo reported no issues and failed anyway, which is credo saying something
  # about itself rather than about the code. Its output is the answer.
  defp report([], output, _exit_code, duration_ms) do
    %{
      name: "Credo",
      status: :error,
      output: output,
      stats: %{issue_count: 0},
      summary: "Check failed (see output)",
      duration_ms: duration_ms
    }
  end

  defp report(issues, output, _exit_code, duration_ms) do
    parsed = findings(issues)

    %{
      name: "Credo",
      status: :error,
      output: output,
      findings: parsed |> Enum.map(&elem(&1, 0)) |> Finding.sort(),
      stats: %{issue_count: length(parsed)},
      summary: summary(parsed),
      duration_ms: duration_ms
    }
  end

  # A run that printed no report either passed silently or broke. Either way
  # there is nothing to parse, so the tool's output stands on its own.
  defp unparsed(output, 0, duration_ms) do
    %{
      name: "Credo",
      status: :ok,
      output: output,
      stats: %{issue_count: 0},
      summary: "No issues",
      duration_ms: duration_ms
    }
  end

  defp unparsed(output, _exit_code, duration_ms) do
    %{
      name: "Credo",
      status: :error,
      output: output,
      stats: %{},
      summary: "Credo did not produce a report",
      duration_ms: duration_ms
    }
  end

  # Findings are carried as `{finding, category}` pairs, because the summary
  # breaks down by category and `check` has already been spent on the check
  # module, which is the more specific of the two.
  defp findings(issues) do
    # Read the umbrella layout once rather than once per finding.
    apps = Umbrella.apps_paths()

    Enum.flat_map(issues, &finding(&1, apps))
  end

  defp finding(%{"message" => message} = issue, apps) when is_binary(message) do
    file = issue |> Map.get("filename", "(unknown)") |> Finding.relative_path()
    category = Map.get(issue, "category")

    finding = %Finding{
      file: file,
      line: position(Map.get(issue, "line_no")),
      column: position(Map.get(issue, "column")),
      app: Umbrella.app_for_path(file, apps),
      severity: Map.get(@severities, category, :info),
      check: Map.get(issue, "check") || category,
      message: message,
      raw: Jason.encode!(issue)
    }

    [{finding, category || "unknown"}]
  end

  defp finding(_issue, _apps), do: []

  defp position(position) when is_integer(position) and position > 0, do: position
  defp position(_other), do: nil

  defp summary(parsed) do
    count = length(parsed)

    "#{count} issue#{plural(count)} (#{breakdown(parsed)})"
  end

  defp plural(1), do: ""
  defp plural(_count), do: "s"

  # The breakdown is by category rather than by check: "3 readability" is what
  # a reader triages on, where thirty check names would be the findings again.
  defp breakdown(parsed) do
    parsed
    |> Enum.frequencies_by(fn {_finding, category} -> category end)
    |> Enum.sort_by(fn {category, _count} -> {order(category), category} end)
    |> Enum.map_join(", ", fn {category, count} -> "#{count} #{category}" end)
  end

  defp order(category) do
    case Enum.find_index(@category_order, &(&1 == category)) do
      nil -> length(@category_order)
      index -> index
    end
  end
end
