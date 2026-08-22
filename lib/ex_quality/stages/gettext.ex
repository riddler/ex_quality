defmodule ExQuality.Stages.Gettext do
  @moduledoc """
  Checks translation completeness by reading the project's `.po` files.

  Reports two kinds of finding, one per untranslated or fuzzy entry, each with
  the file, the line of its `msgid`, and the app it belongs to:

  - missing translations (an empty `msgstr`)
  - fuzzy translations (marked `#, fuzzy`)

  This stage is automatically enabled only if `:gettext` is in deps.

  ## What it reads

  Translations live in `priv/` under whichever project declares the backend, so
  the files are found with a wildcard over the umbrella's child apps as well as
  the root. An umbrella root has no `priv/` of its own: a scan of one hardcoded
  directory there finds nothing, and finding nothing is not the same as finding
  no problems.

  A run that examined no files reports itself as `:skipped` with the reason,
  the way an uninstalled tool does. A stage that said nothing would otherwise
  read as a stage that passed.

  ## The source locale

  A project's source locale is written in the source, so its `.po` files are
  untranslated by definition and every entry in them would be reported. That
  locale is `"en"` unless `gettext: [source_locale: "..."]` says otherwise, and
  a project whose only locale is the source locale is reported as skipped
  rather than green.

  `errors.po` is excluded for the same reason - Phoenix generates it with empty
  entries in every locale - and `gettext: [exclude: [...]]` replaces that list.

  ## Extraction

  `mix gettext.extract --merge` writes: it rewrites `.pot` and `.po` files, and
  it compiles the project to do it. Both are surprises from a checker. A tool
  that dirties the tree lands in every commit as noise, and a stage that
  recompiles while the other stages are reading the same build can pull the
  ground out from under them.

  So it is off by default and this stage reads the committed files as they
  stand. `gettext: [extract: true]` turns it back on, and the stage then
  declares itself a writer (`stage_kind/1`) so the run serialises it rather
  than running it alongside the stages that read the build.
  """

  alias ExQuality.Finding
  alias ExQuality.Stage
  alias ExQuality.Umbrella

  @source_locale "en"
  @exclude ["errors.po"]

  @doc """
  Says whether this stage writes to the project, so a run can keep it away from
  the stages that read the build.

  Extraction compiles the project and rewrites translation files, so a stage
  configured to extract is a `:writer`. Reading `.po` files is not, so the
  default is `:reader`.

      iex> ExQuality.Stages.Gettext.stage_kind([])
      :reader

      iex> ExQuality.Stages.Gettext.stage_kind(gettext: [extract: true])
      :writer
  """
  @spec stage_kind(keyword()) :: ExQuality.Stage.kind()
  def stage_kind(config), do: if(extract?(config), do: :writer, else: :reader)

  @doc """
  Runs the gettext stage.

  ## Config options

  - `gettext.source_locale` - the locale the source is written in, whose files
    are not checked (default: `"en"`)
  - `gettext.exclude` - basenames to skip (default: `["errors.po"]`)
  - `gettext.extract` - run `mix gettext.extract --merge` first, writing to the
    project (default: `false`)
  """
  @spec run(keyword()) :: ExQuality.Stage.result()
  def run(config) do
    start_time = System.monotonic_time(:millisecond)

    case extract(config) do
      :ok -> check_translations(config, start_time)
      {:error, result} -> result
    end
  end

  defp extract(config) do
    if extract?(config) do
      {_output, exit_code} =
        System.cmd("mix", ["gettext.extract", "--merge"],
          env: [{"MIX_ENV", "dev"}],
          stderr_to_stdout: true
        )

      if exit_code == 0, do: :ok, else: {:error, extraction_failed()}
    else
      :ok
    end
  end

  defp extraction_failed do
    %{
      name: "Gettext",
      status: :error,
      output: "Gettext extraction failed",
      findings: [],
      stats: %{},
      summary: "Extraction failed",
      duration_ms: 0
    }
  end

  defp extract?(config) do
    config |> Keyword.get(:gettext, []) |> Keyword.get(:extract, false)
  end

  # Nothing to read is reported as a skip, not a pass, and the two reasons a
  # project can have nothing to read are different problems with different
  # fixes, so they are named separately.
  defp check_translations(config, start_time) do
    case po_files(config) do
      {[], reason} ->
        Stage.skipped("Gettext", reason, :project)

      {files, _reason} ->
        findings = files |> Enum.flat_map(&file_findings/1) |> Finding.sort()
        report(findings, length(files), System.monotonic_time(:millisecond) - start_time)
    end
  end

  # `{app, file}` pairs: the app is what a reader of a ten-app umbrella needs
  # in order to know who owns the translation.
  defp po_files(config) do
    all =
      for {app, root} <- roots(),
          file <- Path.wildcard(Path.join(root, "priv/**/*.po")),
          do: {app, file}

    case {all, Enum.filter(all, &checked?(&1, config))} do
      {[], _checked} -> {[], "no .po files found"}
      {_all, []} -> {[], "no .po files outside the source locale"}
      {_all, checked} -> {checked, nil}
    end
  end

  defp roots do
    case Enum.sort(Umbrella.apps_paths()) do
      [] -> [{nil, "."}]
      apps -> [{nil, "."} | apps]
    end
  end

  defp checked?({_app, file}, config) do
    gettext = Keyword.get(config, :gettext, [])
    locale = Keyword.get(gettext, :source_locale, @source_locale)
    exclude = Keyword.get(gettext, :exclude, @exclude)

    not String.contains?(file, "/#{locale}/") and Path.basename(file) not in exclude
  end

  defp file_findings({app, file}) do
    case File.read(file) do
      {:ok, contents} ->
        lines = String.split(contents, "\n")
        path = Finding.relative_path(file)

        Enum.map(untranslated(lines), &finding(&1, path, app, "missing")) ++
          Enum.map(fuzzy(lines), &finding(&1, path, app, "fuzzy"))

      {:error, _reason} ->
        []
    end
  end

  defp finding({line, msgid}, file, app, check) do
    %Finding{
      file: file,
      line: line,
      app: app,
      severity: :error,
      check: check,
      message: "#{check} translation for \"#{truncate_msgid(msgid)}\"",
      raw: "#{file}:#{line} #{check}: #{msgid}"
    }
  end

  defp report(findings, file_count, duration_ms) do
    {missing, fuzzy} = Enum.split_with(findings, &(&1.check == "missing"))

    %{
      name: "Gettext",
      status: if(findings == [], do: :ok, else: :error),
      output: "",
      findings: findings,
      stats: stats(length(missing), length(fuzzy), file_count),
      summary: summary(length(missing), length(fuzzy), file_count),
      duration_ms: duration_ms
    }
  end

  defp stats(missing, fuzzy, file_count) do
    %{missing_translations: missing, fuzzy_translations: fuzzy, file_count: file_count}
  end

  # A clean run says how much it read, because "all translations complete"
  # over one file and over forty are not the same statement.
  defp summary(0, 0, file_count), do: "All translations complete (#{files(file_count)})"
  defp summary(missing, 0, _count), do: "#{missing} missing translation#{plural(missing)}"
  defp summary(0, fuzzy, _count), do: "#{fuzzy} fuzzy translation#{plural(fuzzy)}"

  defp summary(missing, fuzzy, _count) do
    "#{missing} missing, #{fuzzy} fuzzy translation#{plural(fuzzy)}"
  end

  defp files(1), do: "1 file"
  defp files(count), do: "#{count} files"

  defp plural(1), do: ""
  defp plural(_count), do: "s"

  defp untranslated(lines) do
    lines
    |> Enum.with_index()
    |> Enum.reduce([], fn {line, index}, acc ->
      add_untranslated_if_empty(line, lines, index, acc)
    end)
    |> Enum.reverse()
    |> Enum.reject(fn {_line, msgid} -> msgid == "" end)
  end

  defp add_untranslated_if_empty(line, lines, index, acc) do
    if String.match?(line, ~r/^msgstr ""$/) do
      case find_msgid_before_line_with_number(lines, index) do
        {msgid, line_num} when msgid != "" -> [{line_num + 1, msgid} | acc]
        _no_msgid -> acc
      end
    else
      acc
    end
  end

  defp find_msgid_before_line_with_number(lines, msgstr_index) do
    lines
    |> Enum.take(msgstr_index)
    |> Enum.with_index()
    |> Enum.reverse()
    |> Enum.find(fn {line, _idx} -> String.starts_with?(line, "msgid ") end)
    |> case do
      nil -> {"", 0}
      {msgid_line, line_num} -> {msgid(msgid_line), line_num}
    end
  end

  defp fuzzy(lines) do
    lines
    |> Enum.with_index()
    |> Enum.reduce([], fn {line, index}, acc ->
      add_fuzzy_if_marked(line, lines, index, acc)
    end)
    |> Enum.reverse()
    |> Enum.reject(fn {_line, msgid} -> msgid == "" end)
  end

  defp add_fuzzy_if_marked(line, lines, index, acc) do
    if String.match?(line, ~r/^#,.*\bfuzzy\b/) do
      case find_msgid_after_line_with_number(lines, index) do
        {msgid, line_num} when msgid != "" -> [{line_num + 1, msgid} | acc]
        _no_msgid -> acc
      end
    else
      acc
    end
  end

  defp find_msgid_after_line_with_number(lines, fuzzy_index) do
    lines
    |> Enum.drop(fuzzy_index + 1)
    |> Enum.with_index(fuzzy_index + 1)
    |> Enum.find(fn {line, _idx} -> String.starts_with?(line, "msgid ") end)
    |> case do
      nil -> {"", 0}
      {msgid_line, line_num} -> {msgid(msgid_line), line_num}
    end
  end

  defp msgid(line) do
    line
    |> String.replace(~r/^msgid "/, "")
    |> String.replace(~r/"$/, "")
  end

  defp truncate_msgid(msgid) do
    if String.length(msgid) > 60 do
      String.slice(msgid, 0, 57) <> "..."
    else
      msgid
    end
  end
end
