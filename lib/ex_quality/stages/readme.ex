defmodule ExQuality.Stages.Readme do
  @moduledoc """
  Checks that a package's `README.md` keeps the shape of an introduction and a
  map: what the package is, why it exists, how to install it, one basic-usage
  snippet, and links to the rest grouped by the reader's question.

  Nothing else in the gate reads the README as a whole, so a README drifts
  into a manual one helpful section at a time. This stage checks the shape,
  not the prose: it reads headings, paragraphs, code blocks and list
  indentation, and it never judges a sentence.

      ✓ README: 180 lines, every part present (0.0s)
      ✓ README: 2 warnings: no_why at README.md:1, over_ceiling at README.md:251 (0.0s)
      ✗ README: 2 problems (0.0s)

  Each finding sits at a `file:line` in the README:

      README.md
        1  [warning] no H2 section reads as the Why: none starts with "Why", "What this is for" or "The problem" (no_why)

  ## Rules

  - `no_what` - the README has no H1, or no prose paragraph under it before
    the next heading, or that first paragraph runs over `what_max_lines`
    lines. Badge, image, HTML, blockquote, list and table blocks between the
    H1 and the paragraph are skipped: they are not the What.
  - `no_why` - no H2 starts with "Why", "What this is for" or "The problem".
  - `no_install` - no H2 starts with "Install", or the one that does carries
    no dependency snippet: a code block holding a `{:package, ...}` tuple.
  - `no_basic_usage` - no H2 starts with "Quick start" (or "Quickstart"),
    "Basic usage", "Usage" or "A first", or the first one that does holds no
    code block, more than one, or a block over forty lines. The section runs
    to the next H1 or H2, so its H3s are part of it.
  - `ungrouped_documentation` - an H2 starting with "Documentation" holds a
    link that is not on a nested list item: every link sits under a group
    item (`- Learn`, then the links indented beneath it). The finding is at
    the first such link and counts the rest.
  - `over_ceiling` - the README runs over the line ceiling, 250 by default.
    The finding is at the first line past it.
  - `bad_manifest` - `.claude/diataxis.md` exists and its front matter is
    unclosed, or its `readme_max_lines` is not a positive integer. The
    default ceiling applies, so a broken manifest never stops the stage.

  Headings are matched on the start of their text, ignoring case. Headings
  and blocks inside fenced code are not read as structure.

  ## What it does not check

  Whether a link resolves. That is the Doc links stage's check
  (`ExQuality.Stages.DocLinks`), and this stage does not repeat it: enable
  both for a README that is shaped right and links right.

  ## What it reads

  `README.md` at the project root, and the front matter of
  `.claude/diataxis.md` when that file exists, for one key:

      ---
      readme_max_lines: 300
      ---

  It builds nothing and runs no tool.

  ## Severity

  Findings are warnings by default: the stage reports them, names each one in
  its summary line and in the JSON report, and passes. `severity: :error`
  makes every finding an error and fails the stage on any of them; that is
  the per-project flip once a README has the shape.

  ## Opt-in

  The stage is **off by default**, so no consumer's gate changes on upgrade.
  Enable it in `.quality.exs`:

      readme: [enabled: :auto]                    # on when README.md exists
      readme: [enabled: true]                     # forced
      readme: [enabled: :auto, severity: :error]  # fail on any finding
  """

  alias ExQuality.Finding

  @readme "README.md"
  @manifest ".claude/diataxis.md"

  @default_max_lines 250
  @default_what_max_lines 6
  @max_block_lines 40

  @why ~r/^(why|what this is for|the problem)\b/i
  @install ~r/^install/i
  @basic_usage ~r/^(quick\s?start|basic usage|usage|a first)\b/i
  @documentation ~r/^documentation\b/i

  @dependency_tuple ~r/\{:[a-z_][a-zA-Z0-9_]*\s*,/
  @link ~r/\[[^\]]*\]\s*[\(\[]/

  @doc """
  Runs the README stage.

  ## Config options

  - `enabled` - `false` (default) | `:auto` (on when `README.md` exists) |
    `true` (forced)
  - `severity` - `:warning` (default) | `:error`
  - `what_max_lines` - the longest the first paragraph under the H1 may run
    (default: #{@default_what_max_lines})
  """
  @spec run(keyword()) :: ExQuality.Stage.result()
  def run(config) do
    start_time = System.monotonic_time(:millisecond)
    options = Keyword.get(config, :readme, [])
    root = File.cwd!()

    case severity(options) do
      {:ok, severity} ->
        {findings, line_count} = check(root, options)

        findings
        |> Enum.map(&to_finding(&1, severity))
        |> Finding.sort()
        |> report(severity, line_count, System.monotonic_time(:millisecond) - start_time)

      {:error, message} ->
        %{
          name: "README",
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
        {:error, "readme: [severity: ...] must be :warning or :error, got: #{inspect(other)}"}
    end
  end

  defp report([], _severity, line_count, duration_ms) do
    %{
      name: "README",
      status: :ok,
      output: "",
      stats: %{finding_count: 0},
      summary: "#{line_count} lines, every part present",
      duration_ms: duration_ms
    }
  end

  defp report(findings, severity, _line_count, duration_ms) do
    count = length(findings)

    %{
      name: "README",
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

  ## The checks

  # `{[{file, line, check, message}], line count}`.
  defp check(root, options) do
    case File.read(Path.join(root, @readme)) do
      {:ok, text} ->
        lines = split_lines(text)
        blocks = structure(lines)
        {max_lines, manifest_findings} = max_lines(root)
        what_max = Keyword.get(options, :what_max_lines, @default_what_max_lines)
        h1_line = h1_line(blocks)

        findings =
          manifest_findings ++
            what_findings(blocks, what_max) ++
            why_findings(blocks, h1_line) ++
            install_findings(blocks, h1_line) ++
            basic_usage_findings(blocks, h1_line) ++
            documentation_findings(blocks) ++
            ceiling_findings(length(lines), max_lines)

        {findings, length(lines)}

      {:error, _reason} ->
        {[{@readme, nil, "no_readme", "there is no README.md at the project root"}], 0}
    end
  end

  defp split_lines(text) do
    text
    |> String.split("\n")
    |> then(fn lines ->
      if List.last(lines) == "", do: Enum.drop(lines, -1), else: lines
    end)
  end

  ## Rule: no_what

  defp what_findings(blocks, what_max) do
    case Enum.split_while(blocks, &(not match?({:heading, 1, _text, _line}, &1))) do
      {_before, []} ->
        [{@readme, 1, "no_what", "the README has no H1 title, so it has no What under one"}]

      {_before, [{:heading, 1, _text, h1_line} | after_h1]} ->
        after_h1
        |> Enum.take_while(&(not match?({:heading, _level, _text, _line}, &1)))
        |> Enum.find(&prose?/1)
        |> what_finding(h1_line, what_max)
    end
  end

  defp what_finding(nil, h1_line, _what_max) do
    [
      {@readme, h1_line, "no_what",
       "no prose paragraph under the H1 says what the package is before the next heading"}
    ]
  end

  defp what_finding({:paragraph, line, lines}, _h1_line, what_max) do
    if length(lines) > what_max do
      [
        {@readme, line, "no_what",
         "the first paragraph under the H1 runs #{length(lines)} lines, " <>
           "over the #{what_max} a What may take"}
      ]
    else
      []
    end
  end

  # A paragraph is prose unless its first line opens a badge, image, HTML,
  # blockquote, list or table block.
  defp prose?({:paragraph, _line, [first | _rest]}) do
    not String.match?(first, ~r/^\s*(\[!\[|!\[|<|>|[-*+]\s|\d+[.)]\s|\|)/)
  end

  defp prose?(_block), do: false

  ## Rules: no_why, no_install, no_basic_usage

  defp why_findings(blocks, h1_line) do
    case section(blocks, @why) do
      nil ->
        [
          {@readme, h1_line, "no_why",
           ~s(no H2 section reads as the Why: none starts with "Why", ) <>
             ~s("What this is for" or "The problem")}
        ]

      _section ->
        []
    end
  end

  defp install_findings(blocks, h1_line) do
    case section(blocks, @install) do
      nil ->
        [{@readme, h1_line, "no_install", ~s(no H2 section starts with "Install")}]

      {heading_line, body} ->
        if Enum.any?(code_blocks(body), &dependency?/1) do
          []
        else
          [
            {@readme, heading_line, "no_install",
             "the Install section carries no dependency snippet: " <>
               ~s(no code block holds a {:package, "~> x.y"} tuple)}
          ]
        end
    end
  end

  defp dependency?({:code, _line, lines}),
    do: Enum.any?(lines, &String.match?(&1, @dependency_tuple))

  defp basic_usage_findings(blocks, h1_line) do
    case section(blocks, @basic_usage) do
      nil ->
        [
          {@readme, h1_line, "no_basic_usage",
           ~s(no H2 section starts with "Quick start", "Basic usage", "Usage" or "A first")}
        ]

      {heading_line, body} ->
        code = code_blocks(body)
        count_findings(code, heading_line) ++ length_findings(code)
    end
  end

  defp count_findings([], heading_line) do
    [{@readme, heading_line, "no_basic_usage", "the basic usage section holds no code block"}]
  end

  defp count_findings([_one], _heading_line), do: []

  defp count_findings([_first, {:code, line, _lines} | _rest] = code, _heading_line) do
    [
      {@readme, line, "no_basic_usage",
       "the basic usage section holds #{length(code)} code blocks; it shows one"}
    ]
  end

  defp length_findings(code) do
    for {:code, line, lines} <- code, length(lines) > @max_block_lines do
      {@readme, line, "no_basic_usage",
       "the basic usage code block runs #{length(lines)} lines, over #{@max_block_lines}"}
    end
  end

  ## Rule: ungrouped_documentation

  defp documentation_findings(blocks) do
    case section(blocks, @documentation) do
      nil ->
        []

      {_heading_line, body} ->
        body
        |> Enum.flat_map(fn
          {:paragraph, line, lines} ->
            lines |> Enum.with_index(line) |> Enum.map(&{elem(&1, 1), elem(&1, 0)})

          _other ->
            []
        end)
        |> Enum.filter(fn {_line, text} ->
          String.match?(text, @link) and not nested_item?(text)
        end)
        |> ungrouped_finding()
    end
  end

  defp ungrouped_finding([]), do: []

  defp ungrouped_finding([{line, _text} | rest]) do
    others =
      case length(rest) do
        0 -> ""
        n -> " (and #{n} more line#{plural(n)} below it)"
      end

    [
      {@readme, line, "ungrouped_documentation",
       "a Documentation link is not under a group item; nest it beneath one " <>
         "such as \"- Learn\"#{others}"}
    ]
  end

  defp nested_item?(text), do: String.match?(text, ~r/^(\s{2,}|\t)\s*([-*+]|\d+[.)])\s/)

  ## Rules: over_ceiling, bad_manifest

  defp ceiling_findings(count, max_lines) when count > max_lines do
    [
      {@readme, max_lines + 1, "over_ceiling",
       "the README runs #{count} lines, over the ceiling of #{max_lines}; " <>
         "move the detail to a page and link it"}
    ]
  end

  defp ceiling_findings(_count, _max_lines), do: []

  # `{ceiling, findings}`. The manifest is optional and only its front matter
  # is read; anything wrong with it is a finding and the default ceiling.
  defp max_lines(root) do
    case File.read(Path.join(root, @manifest)) do
      {:ok, text} -> manifest_max_lines(split_lines(text))
      {:error, _reason} -> {@default_max_lines, []}
    end
  end

  defp manifest_max_lines(["---" | rest]) do
    case Enum.split_while(rest, &(String.trim_trailing(&1) != "---")) do
      {_front, []} ->
        {@default_max_lines,
         [
           {@manifest, 1, "bad_manifest",
            "the front matter opened on line 1 never closes; the ceiling stays at " <>
              "#{@default_max_lines}"}
         ]}

      {front, _closed} ->
        front |> Enum.with_index(2) |> Enum.find_value(&max_lines_key/1) |> max_lines_value()
    end
  end

  defp manifest_max_lines(_no_front_matter), do: {@default_max_lines, []}

  defp max_lines_key({text, line}) do
    case Regex.run(~r/^readme_max_lines:\s*(.*?)\s*$/, text) do
      [_match, value] -> {line, value}
      nil -> nil
    end
  end

  defp max_lines_value(nil), do: {@default_max_lines, []}

  defp max_lines_value({line, value}) do
    case Integer.parse(value) do
      {max, ""} when max > 0 ->
        {max, []}

      _other ->
        {@default_max_lines,
         [
           {@manifest, line, "bad_manifest",
            "readme_max_lines is #{inspect(value)}, not a positive integer; the ceiling " <>
              "stays at #{@default_max_lines}"}
         ]}
    end
  end

  ## Structure

  # The README as blocks, each carrying the line it starts on:
  # `{:heading, level, text, line}`, `{:code, line, content lines}` and
  # `{:paragraph, line, lines}`. Fenced code is one block, so a `#` inside it
  # is not a heading.
  defp structure(lines) do
    lines
    |> Enum.with_index(1)
    |> Enum.reduce({[], nil}, &structure_line/2)
    |> close_open_block()
    |> Enum.reverse()
  end

  defp structure_line({text, _line}, {blocks, {:code, start, fence, content}}) do
    if closes_fence?(text, fence),
      do: {[{:code, start, Enum.reverse(content)} | blocks], nil},
      else: {blocks, {:code, start, fence, [text | content]}}
  end

  defp structure_line({text, line}, {blocks, {:paragraph, start, acc} = open}) do
    if continues?(text),
      do: {blocks, {:paragraph, start, [text | acc]}},
      else: structure_line_fresh({text, line}, [close(open) | blocks])
  end

  defp structure_line({text, line}, {blocks, nil}), do: structure_line_fresh({text, line}, blocks)

  # A line read with no paragraph open: it opens a fence, is a heading, is
  # blank, or starts a paragraph.
  defp structure_line_fresh({text, line}, blocks) do
    cond do
      fence = fence(text) -> {blocks, {:code, line, fence, []}}
      heading = heading(text) -> {[heading_block(heading, line) | blocks], nil}
      String.trim(text) == "" -> {blocks, nil}
      true -> {blocks, {:paragraph, line, [text]}}
    end
  end

  defp heading_block({level, title}, line), do: {:heading, level, title, line}

  # A paragraph continues on any non-blank line that opens nothing new.
  defp continues?(text),
    do: String.trim(text) != "" and is_nil(fence(text)) and is_nil(heading(text))

  defp close({:paragraph, start, acc}), do: {:paragraph, start, Enum.reverse(acc)}

  defp close_open_block({blocks, nil}), do: blocks
  defp close_open_block({blocks, {:paragraph, _start, _acc} = open}), do: [close(open) | blocks]
  # An unclosed fence runs to the end of the file, as CommonMark reads it.
  defp close_open_block({blocks, {:code, start, _fence, content}}),
    do: [{:code, start, Enum.reverse(content)} | blocks]

  defp fence(text) do
    case Regex.run(~r/^\s{0,3}(`{3,}|~{3,})/, text) do
      [_match, fence] -> fence
      nil -> nil
    end
  end

  defp closes_fence?(text, fence) do
    case Regex.run(~r/^\s{0,3}(`{3,}|~{3,})\s*$/, text) do
      [_match, closing] ->
        String.first(closing) == String.first(fence) and
          String.length(closing) >= String.length(fence)

      nil ->
        false
    end
  end

  defp heading(text) do
    case Regex.run(~r/^\s{0,3}(\#{1,6})\s+(.*?)\s*#*\s*$/, text) do
      [_match, hashes, title] -> {String.length(hashes), title}
      nil -> nil
    end
  end

  defp h1_line(blocks) do
    Enum.find_value(blocks, 1, fn
      {:heading, 1, _text, line} -> line
      _other -> nil
    end)
  end

  # The first H2 whose text matches, as `{heading line, body blocks}`. The body
  # runs to the next H1 or H2.
  defp section(blocks, pattern) do
    blocks
    |> Enum.drop_while(fn
      {:heading, 2, text, _line} -> not String.match?(text, pattern)
      _other -> true
    end)
    |> case do
      [] ->
        nil

      [{:heading, 2, _text, line} | rest] ->
        {line,
         Enum.take_while(rest, &(not match?({:heading, level, _t, _l} when level <= 2, &1)))}
    end
  end

  defp code_blocks(body), do: Enum.filter(body, &match?({:code, _line, _lines}, &1))

  ## Findings

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
