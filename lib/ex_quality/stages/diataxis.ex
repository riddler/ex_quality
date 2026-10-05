defmodule ExQuality.Stages.Diataxis do
  @moduledoc """
  Checks that each page under a documentation quadrant reads as the kind of
  page its folder says it is: a tutorial teaches, a how-to guide shows the
  steps to a goal, a reference page describes, an explanation gives reasons.

  Pages drift between kinds one helpful paragraph at a time, and a model-based
  audit catches that only when someone runs it. This stage is the cheap,
  deterministic half: it counts a fixed list of language cues on each page and
  reports a page whose cues point clearly at another kind.

      ✓ Diataxis: 12 pages, each reads as its type (0.0s)
      ✓ Diataxis: 1 warning: how_to_title at docs/guides/upgrade.md:1 (0.0s)
      ✗ Diataxis: 2 problems (0.0s)

  ## What it reads

  The front matter of `.claude/diataxis.md`, the project's documentation
  manifest, for its `quadrants:` map:

      ---
      quadrants:
        tutorials: docs/tutorials
        how_to: docs/guides
        reference: docs/reference
        explanation: docs/explanation
      ---

  Then every `.md` file under each of those paths. A page's declared type is
  its folder's quadrant, or the `type:` key in the page's own front matter
  when it has one (`tutorial`, `how-to`, `reference` or `explanation`). A page
  under two quadrant paths belongs to the deeper one. A project without the
  manifest has nothing to read, and the stage reports nothing.

  ## How a page is read

  Fenced code, inline code and link targets are dropped first. Each cue then
  scores for one type:

  - a cue phrase anywhere on the page scores 1 for each time it appears;
  - a cue phrase in the first paragraph under the H1 scores 3 instead (the
    phrases that open each kind of page);
  - an H1 starting "How to" scores 3 for a how-to guide; one starting
    "About" or "Why", or ending "explained", scores 3 for an explanation;
  - "you will" and "you'll", the second-person future, score 1 each for a
    tutorial;
  - imperative steps (list items opening with a verb such as "Run" or "Add")
    score 2 for a how-to guide when there are at least three and they make up
    at least a third of the page's paragraphs and list items.

  A page reads as a type when that type scores at least 3 and more than twice
  any other type. A page whose cues are too few or too mixed is not judged.

  ## Rules

  - `type_mismatch` - the page reads as a different type from the one it
    declares. The message carries every type's score.
  - `how_to_title` - a page declared a how-to guide has an H1 that does not
    start with "How to", or no H1.
  - `bad_type` - the page's front matter carries a `type:` that is not one of
    the four. Its folder's type applies.
  - `bad_manifest` - `.claude/diataxis.md` has front matter that never
    closes, or no `quadrants:` map with a path in it.

  ## Severity

  Findings are warnings by default: the stage reports them, names each one in
  its summary line and in the JSON report, and passes. `severity: :error`
  makes every finding an error and fails the stage on any of them.

  ## Opt-in

  The stage is **off by default**, so no consumer's gate changes on upgrade.
  Enable it in `.quality.exs`:

      diataxis: [enabled: :auto]                    # on when .claude/diataxis.md exists
      diataxis: [enabled: true]                     # forced
      diataxis: [enabled: :auto, severity: :error]  # fail on any finding
  """

  alias ExQuality.Finding

  @manifest ".claude/diataxis.md"

  @types [:tutorial, :how_to, :reference, :explanation]

  @quadrant_keys %{
    "tutorials" => :tutorial,
    "how_to" => :how_to,
    "reference" => :reference,
    "explanation" => :explanation
  }

  @type_values %{
    "tutorial" => :tutorial,
    "tutorials" => :tutorial,
    "how-to" => :how_to,
    "how_to" => :how_to,
    "how-to guide" => :how_to,
    "reference" => :reference,
    "explanation" => :explanation
  }

  @labels %{
    tutorial: "a tutorial",
    how_to: "a how-to guide",
    reference: "a reference page",
    explanation: "an explanation"
  }

  @names %{
    tutorial: "tutorial",
    how_to: "how-to",
    reference: "reference",
    explanation: "explanation"
  }

  # The cue list. Its source is the Diataxis skill's language cues and
  # per-type rules (the diataxis skill's SKILL.md, after diataxis.fr); this is
  # a fixed subset of them that a gate can count without a model. The skill
  # stays the rulebook: a cue changed there is changed here by hand.
  @phrases %{
    tutorial: [
      "in this tutorial",
      "you should now see",
      "you should see",
      "notice that",
      "you have now"
    ],
    how_to: [
      "this guide shows you how to",
      "this guide shows how to",
      "if you want"
    ],
    reference: [
      "this page lists",
      "this page describes",
      "defaults to",
      "the default is",
      "is one of",
      "returns",
      "raises"
    ],
    explanation: [
      "this page explains",
      "the reason for",
      "historically",
      "is preferred over",
      "interacts with",
      "because",
      "trade-off"
    ]
  }

  @second_person_future ["you will", "you'll"]

  @how_to_title ~r/^how to\b/i
  @explanation_title ~r/(^(about|why)\b|\bexplained$)/i

  @imperative_verbs ~w(add call change check configure copy create define delete
                       edit enable install open pass put remove rename replace run
                       set start stop update use write)

  @phrase_score 1
  @opening_score 3
  @title_score 3
  @steps_score 2
  @min_steps 3
  @min_read_score 3

  @doc """
  Runs the Diataxis stage.

  ## Config options

  - `enabled` - `false` (default) | `:auto` (on when `.claude/diataxis.md`
    exists) | `true` (forced)
  - `severity` - `:warning` (default) | `:error`
  """
  @spec run(keyword()) :: ExQuality.Stage.result()
  def run(config) do
    start_time = System.monotonic_time(:millisecond)
    options = Keyword.get(config, :diataxis, [])

    case severity(options) do
      {:ok, severity} ->
        {findings, summary} = check(File.cwd!())

        findings
        |> Enum.map(&to_finding(&1, severity))
        |> Finding.sort()
        |> report(severity, summary, System.monotonic_time(:millisecond) - start_time)

      {:error, message} ->
        %{
          name: "Diataxis",
          status: :error,
          output: message,
          stats: %{},
          summary: message,
          duration_ms: System.monotonic_time(:millisecond) - start_time
        }
    end
  end

  defp severity(options) do
    case Keyword.get(options, :severity, :warning) do
      severity when severity in [:warning, :error] ->
        {:ok, severity}

      other ->
        {:error, "diataxis: [severity: ...] must be :warning or :error, got: #{inspect(other)}"}
    end
  end

  defp report([], _severity, summary, duration_ms) do
    %{
      name: "Diataxis",
      status: :ok,
      output: "",
      stats: %{finding_count: 0},
      summary: summary,
      duration_ms: duration_ms
    }
  end

  defp report(findings, severity, _summary, duration_ms) do
    count = length(findings)

    %{
      name: "Diataxis",
      status: if(severity == :error, do: :error, else: :ok),
      output: Enum.map_join(findings, "\n", & &1.raw),
      findings: findings,
      stats: %{finding_count: count},
      summary: summary(findings, severity),
      duration_ms: duration_ms
    }
  end

  defp summary(findings, :error) do
    count = length(findings)
    "#{count} problem#{plural(count)}"
  end

  # A passing stage prints its summary line and nothing else, so a warning has
  # to be named there or the terminal reader never sees it.
  defp summary(findings, :warning) do
    count = length(findings)
    named = Enum.map_join(findings, ", ", &"#{&1.check} at #{location(&1.file, &1.line)}")

    "#{count} warning#{plural(count)}: #{named}"
  end

  ## The manifest

  # `{[{file, line, check, message}], summary for a clean run}`.
  defp check(root) do
    case File.read(Path.join(root, @manifest)) do
      {:ok, text} ->
        case quadrants(split_lines(text)) do
          {:ok, quadrants} -> check_pages(root, quadrants)
          {:error, finding} -> {[finding], "no quadrants to read"}
        end

      {:error, _reason} ->
        {[], "no #{@manifest}; no pages to read"}
    end
  end

  # The `quadrants:` map in the manifest's front matter, as
  # `[{type, path}]`, or the finding that says why there is none.
  defp quadrants(["---" | rest]) do
    case Enum.split_while(rest, &(String.trim_trailing(&1) != "---")) do
      {_front, []} ->
        {:error, {@manifest, 1, "bad_manifest", "the front matter opened on line 1 never closes"}}

      {front, _closed} ->
        front |> Enum.with_index(2) |> quadrant_entries()
    end
  end

  defp quadrants(_no_front_matter) do
    {:error,
     {@manifest, 1, "bad_manifest", "there is no front matter, so no quadrants: map to read"}}
  end

  defp quadrant_entries(front) do
    entries =
      front
      |> Enum.drop_while(fn {text, _line} ->
        not String.match?(text, ~r/^quadrants:\s*(#.*)?$/)
      end)
      |> Enum.drop(1)
      |> Enum.take_while(fn {text, _line} -> indented_or_blank?(text) end)
      |> Enum.flat_map(&quadrant_entry/1)

    case entries do
      [] ->
        {:error,
         {@manifest, 1, "bad_manifest",
          "the front matter has no quadrants: map naming a path for tutorials, how_to, " <>
            "reference or explanation"}}

      entries ->
        {:ok, entries}
    end
  end

  defp indented_or_blank?(text),
    do:
      String.trim(text) == "" or String.starts_with?(String.trim_leading(text), "#") or
        String.match?(text, ~r/^\s+\S/)

  defp quadrant_entry({text, _line}) do
    with [_match, key, value] <- Regex.run(~r/^\s+([a-z_]+):\s*(.*)$/, text),
         {:ok, type} <- Map.fetch(@quadrant_keys, key),
         path when path != "" <- scalar(value) do
      [{type, path}]
    else
      _other -> []
    end
  end

  # A YAML scalar as the generated manifests write one: bare or quoted, with an
  # optional trailing comment.
  defp scalar(value) do
    cond do
      match = Regex.run(~r/^"([^"]*)"/, value) -> Enum.at(match, 1)
      match = Regex.run(~r/^'([^']*)'/, value) -> Enum.at(match, 1)
      true -> value |> String.split(~r/\s+#/, parts: 2) |> hd() |> String.trim()
    end
  end

  ## The pages

  defp check_pages(root, quadrants) do
    pages = pages(root, quadrants)
    findings = Enum.flat_map(pages, fn {file, type} -> check_page(root, file, type) end)

    {findings, "#{length(pages)} page#{plural(length(pages))}, each reads as its type"}
  end

  # Every `.md` file under a quadrant path, as `[{relative path, {type, path}}]`,
  # each assigned to the deepest quadrant path that holds it.
  defp pages(root, quadrants) do
    quadrants
    |> Enum.flat_map(fn {_type, path} ->
      root |> Path.join(path) |> Path.join("**/*.md") |> Path.wildcard()
    end)
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.map(fn absolute ->
      file = Path.relative_to(absolute, root)
      {file, deepest_quadrant(file, quadrants)}
    end)
  end

  defp deepest_quadrant(file, quadrants) do
    quadrants
    |> Enum.filter(fn {_type, path} -> under?(file, path) end)
    |> Enum.max_by(fn {_type, path} -> length(Path.split(normalize(path))) end)
  end

  defp under?(file, path) do
    prefix = Path.split(normalize(path))
    Enum.take(Path.split(file), length(prefix)) == prefix
  end

  defp normalize(path), do: path |> Path.expand("/") |> Path.relative_to("/")

  defp check_page(root, file, {folder_type, folder}) do
    lines = root |> Path.join(file) |> File.read!() |> split_lines()
    {front, body} = front_matter(lines)
    {declared, by, type_findings} = declared_type(file, front, folder_type, folder)
    page = read_page(body)

    type_findings ++
      mismatch_findings(file, page, declared, by) ++ title_findings(file, page, declared)
  end

  ## Front matter

  # `{[{text, line}] front matter, [{text, line}] body}`. A page with no
  # closing marker has no front matter.
  defp front_matter(lines) do
    numbered = Enum.with_index(lines, 1)

    with [{"---", 1} | rest] <- numbered,
         {front, [{"---", _close} | body]} <- Enum.split_while(rest, &(elem(&1, 0) != "---")) do
      {front, body}
    else
      _other -> {[], numbered}
    end
  end

  # `{type, how it was declared, findings}`.
  defp declared_type(file, front, folder_type, folder) do
    case Enum.find_value(front, &type_key/1) do
      nil ->
        {folder_type, "its folder #{folder}", []}

      {value, line} ->
        case Map.fetch(@type_values, String.downcase(value)) do
          {:ok, type} ->
            {type, "its front matter", []}

          :error ->
            {folder_type, "its folder #{folder}",
             [
               {file, line, "bad_type",
                "type: #{inspect(value)} is not tutorial, how-to, reference or explanation; " <>
                  "its folder's type applies"}
             ]}
        end
    end
  end

  defp type_key({text, line}) do
    case Regex.run(~r/^type:\s*(.*)$/, text) do
      [_match, value] -> {scalar(value), line}
      nil -> nil
    end
  end

  ## Reading a page

  # `%{h1: {text, line} | nil, opening: text, text: text, steps: n, blocks: n}`.
  # Fenced code is dropped; the H1 is the first `# ` heading, the opening is
  # the first paragraph after it.
  defp read_page(body) do
    prose = drop_code(body)
    h1 = Enum.find_value(prose, &h1/1)

    %{
      h1: h1,
      opening: opening(prose, h1),
      text: Enum.map_join(prose, "\n", &clean(elem(&1, 0))),
      steps: Enum.count(prose, &step?/1),
      blocks: count_blocks(prose)
    }
  end

  defp drop_code(lines) do
    lines
    |> Enum.reduce({[], nil}, fn {text, _line} = entry, {kept, fence} ->
      case {fence, fence(text)} do
        {nil, nil} -> {[entry | kept], nil}
        {nil, opened} -> {kept, opened}
        {open, closing} -> {kept, if(closes?(closing, open, text), do: nil, else: open)}
      end
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  defp fence(text) do
    case Regex.run(~r/^\s{0,3}(`{3,}|~{3,})/, text) do
      [_match, fence] -> fence
      nil -> nil
    end
  end

  defp closes?(nil, _open, _text), do: false

  defp closes?(closing, open, text) do
    String.first(closing) == String.first(open) and
      String.length(closing) >= String.length(open) and
      String.match?(text, ~r/^\s{0,3}(`{3,}|~{3,})\s*$/)
  end

  defp h1({text, line}) do
    case Regex.run(~r/^\s{0,3}#\s+(.*?)\s*#*\s*$/, text) do
      [_match, title] -> {title, line}
      nil -> nil
    end
  end

  defp opening(_prose, nil), do: ""

  defp opening(prose, {_title, h1_line}) do
    prose
    |> Enum.drop_while(fn {_text, line} -> line <= h1_line end)
    |> Enum.drop_while(fn {text, _line} -> String.trim(text) == "" end)
    |> Enum.take_while(fn {text, _line} -> String.trim(text) != "" and not heading?(text) end)
    |> Enum.map_join(" ", &clean(elem(&1, 0)))
  end

  defp heading?(text), do: String.match?(text, ~r/^\s{0,3}#/)

  # One line, lowercased, typographic apostrophes made plain, inline code and
  # link targets dropped, so a cue never matches inside code or a URL. Read a
  # line at a time, so a stray backtick never swallows the lines after it.
  defp clean(text) do
    text
    |> String.replace("\u2019", "'")
    |> String.replace(~r/`[^`]*`/, " ")
    |> String.replace(~r/\]\([^)]*\)/, "]")
    |> String.downcase()
  end

  @list_item ~r/^\s*(?:[-*+]|\d+[.)])\s+(.*)$/

  defp step?({text, _line}) do
    case Regex.run(@list_item, text) do
      [_match, item] -> imperative?(item)
      nil -> false
    end
  end

  defp imperative?(item) do
    item
    |> String.replace(~r/^[\s*_`\[]+/, "")
    |> String.split(~r/[^A-Za-z]/, parts: 2)
    |> hd()
    |> String.downcase()
    |> then(&(&1 in @imperative_verbs))
  end

  # Paragraphs and list items: each list item counts, and each run of other
  # non-blank, non-heading lines counts once.
  defp count_blocks(prose) do
    prose
    |> Enum.reduce({0, false}, fn {text, _line}, {count, in_paragraph} ->
      cond do
        String.match?(text, @list_item) -> {count + 1, false}
        String.trim(text) == "" or heading?(text) -> {count, false}
        in_paragraph -> {count, true}
        true -> {count + 1, true}
      end
    end)
    |> elem(0)
  end

  ## Scoring

  defp scores(page) do
    title = if page.h1, do: page.h1 |> elem(0) |> String.trim(), else: ""

    Map.new(@types, fn type ->
      {type,
       phrase_score(type, page) + title_score(type, title) + future_score(type, page) +
         steps_score(type, page)}
    end)
  end

  defp phrase_score(type, page) do
    @phrases
    |> Map.fetch!(type)
    |> Enum.map(fn phrase ->
      if occurrences(page.opening, phrase) > 0,
        do: @opening_score + (occurrences(page.text, phrase) - 1) * @phrase_score,
        else: occurrences(page.text, phrase) * @phrase_score
    end)
    |> Enum.sum()
  end

  defp title_score(:how_to, title),
    do: if(String.match?(title, @how_to_title), do: @title_score, else: 0)

  defp title_score(:explanation, title),
    do: if(String.match?(title, @explanation_title), do: @title_score, else: 0)

  defp title_score(_type, _title), do: 0

  defp future_score(:tutorial, page),
    do: @second_person_future |> Enum.map(&occurrences(page.text, &1)) |> Enum.sum()

  defp future_score(_type, _page), do: 0

  defp steps_score(:how_to, %{steps: steps, blocks: blocks})
       when steps >= @min_steps and steps * 3 >= blocks,
       do: @steps_score

  defp steps_score(_type, _page), do: 0

  defp occurrences(text, phrase) do
    ~r/(?<![a-z'])#{Regex.escape(phrase)}(?![a-z])/
    |> Regex.scan(text)
    |> length()
  end

  # The type a page reads as, or nil when no type is clear.
  defp read_as(scores) do
    [{top, top_score}, {_second, second_score} | _rest] =
      Enum.sort_by(scores, fn {type, score} ->
        {-score, Enum.find_index(@types, &(&1 == type))}
      end)

    if top_score >= @min_read_score and top_score > 2 * second_score, do: top
  end

  ## Rules: type_mismatch, how_to_title

  defp mismatch_findings(file, page, declared, by) do
    scores = scores(page)

    case read_as(scores) do
      read when read in [nil, declared] ->
        []

      read ->
        [
          {file, h1_line(page), "type_mismatch",
           "declared #{@labels[declared]} by #{by}, but reads as #{@labels[read]} " <>
             "(#{score_line(scores)})"}
        ]
    end
  end

  defp score_line(scores),
    do: Enum.map_join(@types, ", ", &"#{@names[&1]} #{Map.fetch!(scores, &1)}")

  defp title_findings(file, %{h1: nil}, :how_to) do
    [{file, 1, "how_to_title", ~s(a how-to guide has no H1; title it "How to ...")}]
  end

  defp title_findings(file, %{h1: {title, line}}, :how_to) do
    if String.match?(title, @how_to_title),
      do: [],
      else: [
        {file, line, "how_to_title",
         ~s(a how-to guide's H1 starts "How to"; this one is #{inspect(title)})}
      ]
  end

  defp title_findings(_file, _page, _type), do: []

  defp h1_line(%{h1: {_title, line}}), do: line
  defp h1_line(_page), do: 1

  ## Shared

  # Lines without their endings, CRLF included, and without the empty string
  # a final newline leaves.
  defp split_lines(text) do
    text
    |> String.split(~r/\r?\n/)
    |> then(fn lines ->
      if List.last(lines) == "", do: Enum.drop(lines, -1), else: lines
    end)
  end

  defp to_finding({file, line, check, message}, severity) do
    %Finding{
      file: file,
      line: line,
      severity: severity,
      check: check,
      message: message,
      raw: "#{location(file, line)}: #{message}"
    }
  end

  defp location(file, nil), do: file
  defp location(file, line), do: "#{file}:#{line}"

  defp plural(1), do: ""
  defp plural(_count), do: "s"
end
