defmodule ExQuality.Stages.Sobelow do
  @moduledoc """
  Runs Sobelow security static analysis on Phoenix applications.

  Sobelow reports findings at three confidence levels, but only the ones at or
  above the project's `exit:` threshold actually block a build. Printing all
  three levels on every run trains a reader to ignore the output, so this stage
  separates the two: findings at or above the threshold are reported as
  `severity: :error` and rendered, and the rest are reported as a count only.

      ✗ Sobelow: 2 blocking findings (1 high, 1 medium), 3 informational not shown

  Set `sobelow: [show_informational: true]` in `.quality.exs`, or pass
  `--verbose`, to render the informational ones too.

  ## Threshold

  The `exit:` setting in `.sobelow-conf` decides what blocks. It is the
  project's security decision, so it wins over anything in `.quality.exs`;
  `sobelow: [exit: "high"]` there only supplies a default for a project with no
  `.sobelow-conf`, and the default when neither says is `"medium"`.

  ExQuality never proposes editing `.sobelow-conf` as a remedy. A tool that
  silences its own findings to go green is a regression dressed as a pass.

  ## How the tool is invoked

  `mix sobelow --config` replaces every other command line option with the
  contents of `.sobelow-conf`, including the output format, so this stage reads
  that file itself and passes the parts it understands (`ignore`,
  `ignore_files`, `router`, `skip`, `threshold`) as switches alongside
  `--format json`. The report is written with `--out` rather than read from
  stdout, so tool chatter on either stream cannot corrupt it.

  `--exit` is never passed. The stage decides pass or fail from the findings it
  parsed, which is the same decision made against the same threshold, and it
  keeps a scan that found nothing blocking from being indistinguishable from a
  scan that did not run.

  ## Umbrellas

  `mix sobelow` at an umbrella root finds no application to scan and exits 0,
  so the stage fans out over the child apps itself, one `--root` per app, in
  parallel. Each app reads its own `.sobelow-conf` and each finding is tagged
  with its app.

  Only apps that declare `:phoenix` or `:sobelow` are scanned. Sobelow has
  nothing to say about the others, and a run that named every one of them as
  unscanned would spend most of its output on apps a reader has no action to
  take on.
  """

  alias ExQuality.Aliases
  alias ExQuality.Finding
  alias ExQuality.Umbrella

  @confidences [:high, :medium, :low]
  @blocking %{
    high: [:high],
    medium: [:high, :medium],
    low: [:high, :medium, :low],
    none: []
  }

  @doc """
  Runs the sobelow stage.

  ## Config options

  - `exit` - default threshold when `.sobelow-conf` sets none (default: `"medium"`)
  - `show_informational` - render findings below the threshold (default: false)
  """
  @spec run(keyword()) :: ExQuality.Stage.result()
  def run(config) do
    if Aliases.shadowing?("sobelow") do
      Aliases.shadowed("Sobelow", "sobelow")
    else
      scan_project(config)
    end
  end

  defp scan_project(config) do
    start_time = System.monotonic_time(:millisecond)
    scans = scan_all(targets(), config)
    duration_ms = System.monotonic_time(:millisecond) - start_time

    case Enum.filter(scans, &(&1.report == nil)) do
      [] -> report(scans, config, duration_ms)
      failed -> tool_failure(failed, duration_ms)
    end
  end

  # A single-app project is scanned where it stands; an umbrella is scanned one
  # app at a time, in parallel, because the root has nothing sobelow can read.
  defp targets do
    case scannable_apps() do
      [] -> [{nil, nil}]
      apps -> apps
    end
  end

  defp scannable_apps do
    deps = Umbrella.app_deps()

    for {app, path} <- Enum.sort(Umbrella.apps_paths()),
        scannable?(Map.get(deps, app, [])),
        do: {app, path}
  end

  defp scannable?(deps) do
    Enum.any?(deps, fn dep -> elem(dep, 0) in [:phoenix, :sobelow] end)
  end

  # One app per task: an umbrella's apps are independent scans, and a ten-app
  # umbrella run should not cost ten times a single-app one.
  defp scan_all([target], config), do: [scan(target, config)]

  defp scan_all(targets, config) do
    targets
    |> Task.async_stream(&scan(&1, config), timeout: :infinity, ordered: true)
    |> Enum.map(fn {:ok, scan} -> scan end)
  end

  defp scan({app, path}, config) do
    conf = read_conf(path)
    out = out_path()

    {output, _exit_code} =
      System.cmd("mix", build_args(path, conf, out),
        env: [{"MIX_ENV", "dev"}],
        stderr_to_stdout: true
      )

    %{
      app: app,
      output: output,
      threshold: exit_threshold(conf, config),
      report: read_report(out, output)
    }
  end

  defp out_path do
    Path.join(System.tmp_dir!(), "ex_quality-sobelow-#{:erlang.unique_integer([:positive])}.json")
  end

  # The report is normally the `--out` file. An older sobelow that does not
  # know the switch still prints the JSON, so stdout is tried as a fallback
  # before the scan is called a failure.
  defp read_report(out, output) do
    case File.read(out) do
      {:ok, contents} ->
        _removed = File.rm(out)
        decode(contents)

      {:error, _reason} ->
        decode(output)
    end
  end

  defp decode(contents) do
    case Jason.decode(contents) do
      {:ok, %{"findings" => _findings} = report} -> report
      _other -> nil
    end
  end

  defp build_args(path, conf, out) do
    ["sobelow", "--format", "json", "--private", "--out", out] ++
      root_args(path) ++
      conf_args(conf)
  end

  defp root_args(nil), do: []
  defp root_args(path), do: ["--root", path]

  # Everything sobelow's own config file says about *what* to scan is passed
  # through. What it says about output is not: this stage owns that.
  defp conf_args(conf) do
    Enum.flat_map(conf, fn
      {:skip, true} -> ["--skip"]
      {:router, router} when is_binary(router) and router != "" -> ["--router", router]
      {:threshold, level} when is_binary(level) -> ["--threshold", level]
      {:ignore, value} -> list_arg("--ignore", value)
      {:ignore_files, value} -> list_arg("--ignore-files", value)
      _other -> []
    end)
  end

  defp list_arg(switch, value) do
    case value |> List.wrap() |> Enum.reject(&(&1 == "")) do
      [] -> []
      values -> [switch, Enum.join(values, ",")]
    end
  end

  # `.sobelow-conf` is a keyword list literal. A file that will not evaluate is
  # treated as absent: sobelow reports that far better than this stage could.
  defp read_conf(path) do
    file = Path.join(path || ".", ".sobelow-conf")

    if File.exists?(file) do
      case Code.eval_file(file) do
        {conf, _bindings} when is_list(conf) -> conf
        _other -> []
      end
    else
      []
    end
  rescue
    _error -> []
  end

  defp exit_threshold(conf, config) do
    quality_default = config |> Keyword.get(:sobelow, []) |> Keyword.get(:exit, "medium")

    conf
    |> Keyword.get(:exit, quality_default)
    |> normalize_threshold()
  end

  defp normalize_threshold(level) when is_atom(level) and not is_nil(level) do
    level |> Atom.to_string() |> normalize_threshold()
  end

  defp normalize_threshold(level) when is_binary(level) do
    case String.downcase(level) do
      "high" -> :high
      "medium" -> :medium
      "low" -> :low
      _other -> :none
    end
  end

  defp normalize_threshold(_other), do: :none

  # A scan that produced no report is a broken tool invocation, not a clean
  # bill of health, so it fails loudly with whatever the tool did say.
  defp tool_failure(failed, duration_ms) do
    %{
      name: "Sobelow",
      status: :error,
      output: Enum.map_join(failed, "\n", & &1.output),
      stats: %{},
      summary: failure_summary(failed),
      duration_ms: duration_ms
    }
  end

  defp failure_summary([%{app: nil}]), do: "Sobelow did not produce a report"

  defp failure_summary(failed) do
    apps = Enum.map_join(failed, ", ", &to_string(&1.app))
    "Sobelow did not produce a report (#{apps})"
  end

  defp report(scans, config, duration_ms) do
    {blocking, informational} = split_findings(scans)
    stats = stats(blocking, informational)

    %{
      name: "Sobelow",
      status: if(blocking == [], do: :ok, else: :error),
      output: Enum.map_join(scans, "\n", & &1.output),
      findings: shown_findings(blocking, informational, config),
      stats: stats,
      summary: summary(stats, config),
      duration_ms: duration_ms
    }
  end

  # Only the findings a reader is expected to act on are rendered. The rest are
  # counted in the summary, so they are never silently dropped.
  defp shown_findings(blocking, informational, config) do
    shown = if show_informational?(config), do: blocking ++ informational, else: blocking

    shown |> Enum.map(&elem(&1, 0)) |> Finding.sort()
  end

  defp show_informational?(config) do
    Keyword.get(config, :verbose, false) or
      config |> Keyword.get(:sobelow, []) |> Keyword.get(:show_informational, false)
  end

  # Findings are carried as `{finding, confidence}` pairs, because the
  # confidence is what the summary breaks down and `severity` has already been
  # spent saying whether the finding blocks.
  defp split_findings(scans) do
    scans
    |> Enum.flat_map(&scan_findings/1)
    |> Enum.split_with(fn {finding, _confidence} -> finding.severity == :error end)
  end

  defp scan_findings(scan) do
    blocking = Map.fetch!(@blocking, scan.threshold)

    Enum.flat_map(@confidences, fn confidence ->
      scan.report
      |> entries(confidence)
      |> Enum.flat_map(&finding(&1, scan.app, confidence, confidence in blocking))
    end)
  end

  defp entries(report, confidence) do
    report
    |> Map.get("findings", %{})
    |> Map.get("#{confidence}_confidence", [])
    |> List.wrap()
  end

  defp finding(entry, app, confidence, blocking?) when is_map(entry) do
    {check, message} = split_type(Map.get(entry, "type", "Finding"))

    finding = %Finding{
      file: entry |> Map.get("file", "(unknown)") |> Finding.relative_path(),
      line: line(Map.get(entry, "line")),
      app: app,
      severity: if(blocking?, do: :error, else: :info),
      check: check,
      message: describe(message, confidence, Map.get(entry, "variable")),
      raw: Jason.encode!(entry)
    }

    [{finding, confidence}]
  end

  defp finding(_entry, _app, _confidence, _blocking?), do: []

  # Sobelow's finding type is "Module.Check: Description".
  defp split_type(type) do
    case String.split(type, ": ", parts: 2) do
      [check, message] -> {check, message}
      [message] -> {nil, message}
    end
  end

  # The rendered message names the confidence, because a reader triaging a
  # finding needs to know how sure the tool is about it.
  defp describe(message, confidence, variable) do
    "#{message} (#{confidence} confidence)#{variable_suffix(variable)}"
  end

  defp variable_suffix(nil), do: ""
  defp variable_suffix(""), do: ""
  defp variable_suffix(variable), do: ": #{variable}"

  # Sobelow reports line 0 for a finding it could not place.
  defp line(line) when is_integer(line) and line > 0, do: line
  defp line(_other), do: nil

  defp stats(blocking, informational) do
    %{
      finding_count: length(blocking) + length(informational),
      blocking_count: length(blocking),
      informational_count: length(informational),
      blocking_by_confidence: by_confidence(blocking)
    }
  end

  defp by_confidence(findings) do
    counts = Enum.frequencies_by(findings, fn {_finding, confidence} -> confidence end)

    for confidence <- @confidences,
        count = Map.get(counts, confidence, 0),
        count > 0,
        do: {to_string(confidence), count}
  end

  defp summary(%{blocking_count: 0, informational_count: 0}, _config), do: "No findings"

  defp summary(%{blocking_count: 0} = stats, config) do
    "No blocking findings#{informational_suffix(stats, config)}"
  end

  defp summary(stats, config) do
    "#{stats.blocking_count} blocking finding#{plural(stats.blocking_count)}" <>
      breakdown(stats.blocking_by_confidence) <>
      informational_suffix(stats, config)
  end

  defp breakdown([]), do: ""

  defp breakdown(counts) do
    " (" <> Enum.map_join(counts, ", ", fn {name, count} -> "#{count} #{name}" end) <> ")"
  end

  defp informational_suffix(%{informational_count: 0}, _config), do: ""

  defp informational_suffix(%{informational_count: count}, config) do
    if show_informational?(config) do
      ", #{count} informational"
    else
      ", #{count} informational not shown"
    end
  end

  defp plural(1), do: ""
  defp plural(_count), do: "s"
end
