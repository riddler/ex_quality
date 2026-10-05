defmodule ExQuality.Stages.ReadmeTest do
  # Each test writes a README into a temporary directory and runs the stage
  # from there, and the working directory is global, so this module cannot
  # run alongside the others.
  use ExUnit.Case, async: false

  alias ExQuality.Stage
  alias ExQuality.Stages.Readme

  @moduletag :tmp_dir

  @badges """
  [![Hex.pm Version](https://img.shields.io/hexpm/v/widget.svg)](https://hex.pm/packages/widget)
  [![Hex Docs](https://img.shields.io/badge/hex-docs-lightgreen.svg)](https://hexdocs.pm/widget/)
  """

  @what """
  Widget turns a list of numbers into a running total, one step at a time,
  and tells you which step went over a limit.
  """

  @why """
  ## Why

  Summing a list is one line; knowing where it went wrong is not.
  """

  @install """
  ## Installation

  ```elixir
  def deps do
    [{:widget, "~> 1.2"}]
  end
  ```
  """

  @usage """
  ## Quick start

  ```elixir
  Widget.total([1, 2, 3])
  #=> 6
  ```

  ### Notes

  The total is an integer when every input is.
  """

  @documentation """
  ## Documentation

  - Learn
    - [The first total](docs/tutorials/first-total.md)
  - Look up
    - [Options](docs/reference/options.md)
  """

  defp readme(parts), do: Enum.join(parts, "\n")

  defp clean, do: readme(["# Widget\n", @badges, @what, @why, @install, @usage, @documentation])

  defp run_in(dir, text, config \\ []) do
    if text, do: File.write!(Path.join(dir, "README.md"), text)
    File.cd!(dir, fn -> Readme.run(config) end)
  end

  defp checks(result), do: Enum.map(Stage.findings(result), &{&1.check, &1.line})

  defp by_check(result, check), do: Enum.filter(Stage.findings(result), &(&1.check == check))

  defp line_of(text, needle) do
    text
    |> String.split("\n")
    |> Enum.find_index(&String.contains?(&1, needle))
    |> Kernel.+(1)
  end

  describe "run/1 - a README with every part" do
    # Sabotage: made `fence/1` match no fence - red, this test and the next
    # one (the fenced "## Why" read as a heading) among eight.
    test "passes with no findings and says how long it is", %{tmp_dir: dir} do
      text = clean()
      result = run_in(dir, text)

      assert result.name == "README"
      assert result.status == :ok
      assert Stage.findings(result) == []
      assert result.stats.finding_count == 0

      lines = text |> String.split("\n") |> length() |> Kernel.-(1)
      assert result.summary == "#{lines} lines, every part present"
    end

    test "reads no structure inside fenced code", %{tmp_dir: dir} do
      fenced = """
      ## Usage notes

      ```
      ## Why
      ## Install {:fake, "~> 0.1"}
      ```
      """

      text = readme(["# Widget\n", @what, fenced])
      result = run_in(dir, text)

      assert {"no_why", 1} in checks(result)
      assert {"no_install", 1} in checks(result)
    end
  end

  describe "run/1 - no_what" do
    # Sabotage: made `prose?/1` read a badge line as prose - red, "badges
    # skipped" and "over the line count" (the badges became the What). Made
    # the length check `>=` - red, "what_max_lines moves the line count".
    test "a README with no H1", %{tmp_dir: dir} do
      result = run_in(dir, readme([@what, @why, @install, @usage]))

      assert [finding] = by_check(result, "no_what")
      assert finding.line == 1
      assert finding.file == "README.md"
      assert finding.message =~ "no H1"
    end

    test "no prose paragraph before the next heading, badges skipped", %{tmp_dir: dir} do
      text =
        readme(["# Widget\n", @badges, "> A quote is not the What.\n", @why, @install, @usage])

      result = run_in(dir, text)

      assert [finding] = by_check(result, "no_what")
      assert finding.line == 1
      assert finding.message =~ "no prose paragraph under the H1"
    end

    test "a first paragraph over the line count, at its first line", %{tmp_dir: dir} do
      long = Enum.map_join(1..7, "\n", &"Sentence #{&1} of a What that keeps going.") <> "\n"
      text = readme(["# Widget\n", @badges, long, @why, @install, @usage])
      result = run_in(dir, text)

      assert [finding] = by_check(result, "no_what")
      assert finding.line == line_of(text, "Sentence 1 ")
      assert finding.message =~ "runs 7 lines, over the 6"
    end

    test "what_max_lines moves the line count", %{tmp_dir: dir} do
      text = clean()

      assert by_check(run_in(dir, text, readme: [what_max_lines: 2]), "no_what") == []

      assert [finding] = by_check(run_in(dir, text, readme: [what_max_lines: 1]), "no_what")
      assert finding.message =~ "runs 2 lines, over the 1"
    end
  end

  describe "run/1 - no_why" do
    # Sabotage: made the Why pattern match only "Why" - red, "What this is
    # for" and "The problem" reported no_why.
    test "no H2 reads as the Why, reported at the H1", %{tmp_dir: dir} do
      text = readme(["\n# Widget\n", @what, @install, @usage])
      result = run_in(dir, text)

      assert [finding] = by_check(result, "no_why")
      assert finding.line == 2
    end

    test "each heading the Why may start with is accepted, ignoring case", %{tmp_dir: dir} do
      for heading <- ["Why a widget", "WHAT THIS IS FOR", "The problem it solves"] do
        why = "## #{heading}\n\nSumming is easy; finding the bad step is not.\n"
        text = readme(["# Widget\n", @what, why, @install, @usage])

        assert by_check(run_in(dir, text), "no_why") == [], heading
      end
    end
  end

  describe "run/1 - no_install" do
    test "no Install H2", %{tmp_dir: dir} do
      result = run_in(dir, readme(["# Widget\n", @what, @why, @usage]))

      assert [finding] = by_check(result, "no_install")
      assert finding.line == 1
      assert finding.message =~ ~s(starts with "Install")
    end

    # Sabotage: made `dependency?/1` return true for every block - red, the
    # snippet without a tuple passed.
    test "an Install H2 without a dependency snippet, at the heading", %{tmp_dir: dir} do
      install = "## Install\n\n```\nmix deps.get\n```\n"
      text = readme(["# Widget\n", @what, @why, install, @usage])
      result = run_in(dir, text)

      assert [finding] = by_check(result, "no_install")
      assert finding.line == line_of(text, "## Install")
      assert finding.message =~ "no dependency snippet"
    end
  end

  describe "run/1 - no_basic_usage" do
    test "no basic usage H2", %{tmp_dir: dir} do
      result = run_in(dir, readme(["# Widget\n", @what, @why, @install]))

      assert [finding] = by_check(result, "no_basic_usage")
      assert finding.line == 1
    end

    test "each heading the basic usage may start with is accepted", %{tmp_dir: dir} do
      for heading <- ["Quickstart", "Basic usage", "Usage", "A first total"] do
        usage = "## #{heading}\n\n```elixir\nWidget.total([1])\n```\n"
        text = readme(["# Widget\n", @what, @why, @install, usage])

        assert by_check(run_in(dir, text), "no_basic_usage") == [], heading
      end
    end

    test "a basic usage section with no code block, at the heading", %{tmp_dir: dir} do
      usage = "## Usage\n\nCall `Widget.total/1`.\n"
      text = readme(["# Widget\n", @what, @why, @install, usage])

      assert [finding] = by_check(run_in(dir, text), "no_basic_usage")
      assert finding.line == line_of(text, "## Usage")
      assert finding.message =~ "no code block"
    end

    # Sabotage: made `count_findings/2` accept any number of blocks - red,
    # the two-block section passed.
    test "more than one code block, at the second one", %{tmp_dir: dir} do
      usage =
        "## Usage\n\n```elixir\nWidget.total([1])\n```\n\n~~~elixir\nWidget.total([2])\n~~~\n"

      text = readme(["# Widget\n", @what, @why, @install, usage])

      assert [finding] = by_check(run_in(dir, text), "no_basic_usage")
      assert finding.line == line_of(text, "~~~elixir")
      assert finding.message =~ "holds 2 code blocks"
    end

    # Sabotage: made the block limit 400 - red, the 41-line block passed.
    test "a code block over forty lines, at the block", %{tmp_dir: dir} do
      body = Enum.map_join(1..41, "\n", &"Widget.total([#{&1}])")
      usage = "## Usage\n\n```elixir\n#{body}\n```\n"
      text = readme(["# Widget\n", @what, @why, @install, usage])

      assert [finding] = by_check(run_in(dir, text), "no_basic_usage")
      assert finding.line == line_of(text, "## Usage") + 2
      assert finding.message =~ "runs 41 lines, over 40"

      forty = Enum.map_join(1..40, "\n", &"Widget.total([#{&1}])")
      text = readme(["# Widget\n", @what, @why, @install, "## Usage\n\n```\n#{forty}\n```\n"])
      assert by_check(run_in(dir, text), "no_basic_usage") == []
    end
  end

  describe "run/1 - ungrouped_documentation" do
    # Sabotage: made `nested_item?/1` true for every line - red, the
    # top-level links passed.
    test "a link on a top-level item, at the first one, counting the rest", %{tmp_dir: dir} do
      docs = """
      ## Documentation

      - [Options](docs/reference/options.md)
      - [Guides](docs/guides/index.md)
      - Learn
        - [The first total](docs/tutorials/first-total.md)
      """

      text = readme(["# Widget\n", @what, @why, @install, @usage, docs])
      result = run_in(dir, text)

      assert [finding] = by_check(result, "ungrouped_documentation")
      assert finding.line == line_of(text, "- [Options]")
      assert finding.message =~ "(and 1 more line below it)"
    end

    test "a link in a prose line of the section", %{tmp_dir: dir} do
      docs = "## Documentation\n\nSee [the guides](docs/guides/index.md).\n"
      text = readme(["# Widget\n", @what, @why, @install, @usage, docs])

      assert [finding] = by_check(run_in(dir, text), "ungrouped_documentation")
      assert finding.line == line_of(text, "See [the guides]")
    end

    test "a README with no Documentation section has nothing to group", %{tmp_dir: dir} do
      text = readme(["# Widget\n", @what, @why, @install, @usage])

      assert by_check(run_in(dir, text), "ungrouped_documentation") == []
    end
  end

  describe "run/1 - over_ceiling and the manifest" do
    defp long_readme(lines) do
      base = clean()
      used = base |> String.split("\n") |> length() |> Kernel.-(1)
      base <> String.duplicate("filler\n", lines - used)
    end

    defp write_manifest(dir, text) do
      File.mkdir_p!(Path.join(dir, ".claude"))
      File.write!(Path.join(dir, ".claude/diataxis.md"), text)
    end

    # Sabotage: made `ceiling_findings/2` compare with `>=` - red, the
    # 250-line README reported over_ceiling.
    test "over 250 lines by default, at the first line past it", %{tmp_dir: dir} do
      assert by_check(run_in(dir, long_readme(250)), "over_ceiling") == []

      assert [finding] = by_check(run_in(dir, long_readme(251)), "over_ceiling")
      assert finding.line == 251
      assert finding.message =~ "runs 251 lines, over the ceiling of 250"
    end

    # Sabotage: made `max_lines_key/1` match nothing - red, the manifest's
    # 300 was ignored and the 260-line README reported over_ceiling.
    test "readme_max_lines in .claude/diataxis.md overrides the ceiling", %{tmp_dir: dir} do
      write_manifest(dir, "---\nexample_world: none\nreadme_max_lines: 300\n---\n\n# Docs\n")
      assert by_check(run_in(dir, long_readme(260)), "over_ceiling") == []

      write_manifest(dir, "---\nreadme_max_lines: 40\n---\n")

      assert [finding] =
               by_check(run_in(dir, clean() <> String.duplicate("x\n", 10)), "over_ceiling")

      assert finding.line == 41
    end

    test "a manifest with no front matter keeps the default", %{tmp_dir: dir} do
      write_manifest(dir, "# Docs manifest\n\nreadme_max_lines: 10\n")
      result = run_in(dir, clean())

      assert Stage.findings(result) == []
    end

    test "an unclosed front matter is a finding, and the default applies", %{tmp_dir: dir} do
      write_manifest(dir, "---\nreadme_max_lines: 10\n")
      result = run_in(dir, clean())

      assert [finding] = by_check(result, "bad_manifest")
      assert {finding.file, finding.line} == {".claude/diataxis.md", 1}
      assert by_check(result, "over_ceiling") == []
    end

    test "a value that is not a positive integer is a finding at its line", %{tmp_dir: dir} do
      for value <- ["lots", "0", "-5", "12.5", ""] do
        write_manifest(dir, "---\nexample_world: none\nreadme_max_lines: #{value}\n---\n")
        result = run_in(dir, long_readme(251))

        assert [finding] = by_check(result, "bad_manifest")
        assert finding.line == 3
        assert finding.message =~ "not a positive integer"
        assert [_over] = by_check(result, "over_ceiling")
      end
    end
  end

  describe "run/1 - severity" do
    # Sabotage: made `report/4` return :ok whatever the severity - red, the
    # error-severity run passed.
    test "warnings by default: the stage passes and names each finding", %{tmp_dir: dir} do
      result = run_in(dir, readme(["# Widget\n", @what, @install, @usage]))

      assert result.status == :ok
      assert [finding] = Stage.findings(result)
      assert finding.severity == :warning
      assert result.summary == "1 warning: no_why at README.md:1"
      assert result.output =~ "README.md:1: no H2 section reads as the Why"
    end

    test "severity: :error fails the stage on any finding", %{tmp_dir: dir} do
      text = readme(["# Widget\n", @what, @install])
      result = run_in(dir, text, readme: [severity: :error])

      assert result.status == :error
      assert Enum.all?(Stage.findings(result), &(&1.severity == :error))
      assert result.summary == "2 problems"

      assert run_in(dir, clean(), readme: [severity: :error]).status == :ok
    end

    test "an unknown severity fails the stage and says what it accepts", %{tmp_dir: dir} do
      result = run_in(dir, clean(), readme: [severity: :fatal])

      assert result.status == :error
      assert result.summary =~ "must be :warning or :error, got: :fatal"
    end

    test "a forced run with no README reports it", %{tmp_dir: dir} do
      result = run_in(dir, nil, readme: [severity: :error])

      assert result.status == :error
      assert [%{check: "no_readme", file: "README.md", line: nil}] = Stage.findings(result)
    end
  end
end
