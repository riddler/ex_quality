defmodule ExQuality.Stages.DiataxisTest do
  # Each test writes a manifest and pages into a temporary directory and runs
  # the stage from there, and the working directory is global, so this module
  # cannot run alongside the others.
  use ExUnit.Case, async: false

  alias ExQuality.Stage
  alias ExQuality.Stages.Diataxis

  @moduletag :tmp_dir

  @manifest """
  ---
  docs_root: docs
  quadrants:
    tutorials: docs/tutorials
    how_to: docs/guides
    reference: docs/reference
    explanation: docs/explanation
  readme: README.md
  ---

  The documentation manifest.
  """

  @tutorial """
  # Your first total

  In this tutorial, you will add up a short list of numbers and watch the
  total change as each one arrives.

  1. Start a session with `iex -S mix`.
  2. Call `Widget.total([1, 2, 3])`.

  You should now see `6`. Notice that the total is an integer, because every
  input was one.
  """

  @how_to """
  # How to stop a total at a limit

  This guide shows you how to stop a running total once it passes a limit.

  1. Add `limit: 10` to the options.
  2. Run the total again.
  3. Check the step the result names.

  If you want the total to carry on past the limit, leave `limit` out.
  """

  @reference """
  # Options

  This page lists every option `Widget.total/2` accepts.

  | Option | Type | Default |
  |---|---|---|
  | `:limit` | integer | `nil` |

  `:limit` defaults to `nil`. With no limit, the call returns the sum; with
  one, it returns the sum and the step that passed it.
  """

  @explanation """
  # Why totals stay integers

  This page explains why a total of integers is never a float.

  The reason for it is that a float loses precision as it grows, and a
  running total grows on every step. Integers are preferred because the sum
  stays exact, rather than drifting by a rounding error each time.
  """

  defp write!(dir, path, text) do
    file = Path.join(dir, path)
    File.mkdir_p!(Path.dirname(file))
    File.write!(file, text)
  end

  defp run_in(dir, pages, config \\ [], manifest \\ @manifest) do
    if manifest, do: write!(dir, ".claude/diataxis.md", manifest)
    Enum.each(pages, fn {path, text} -> write!(dir, path, text) end)
    File.cd!(dir, fn -> Diataxis.run(config) end)
  end

  defp checks(result), do: Enum.map(Stage.findings(result), &{&1.check, &1.file, &1.line})

  defp one_page_per_type do
    [
      {"docs/tutorials/first-total.md", @tutorial},
      {"docs/guides/limits.md", @how_to},
      {"docs/reference/options.md", @reference},
      {"docs/explanation/integers.md", @explanation}
    ]
  end

  describe "run/1 - a page per type that reads as its folder" do
    # Sabotage: mapped the manifest's how_to key to the reference type - red,
    # nine tests here and in the how_to_title and manifest blocks.
    test "passes with no findings and counts the pages", %{tmp_dir: dir} do
      result = run_in(dir, one_page_per_type())

      assert result.name == "Diataxis"
      assert result.status == :ok
      assert Stage.findings(result) == []
      assert result.stats.finding_count == 0
      assert result.summary == "4 pages, each reads as its type"
    end

    test "reads pages in subfolders of a quadrant", %{tmp_dir: dir} do
      result = run_in(dir, [{"docs/guides/totals/limits.md", @how_to}])

      assert result.summary == "1 page, each reads as its type"
    end
  end

  describe "run/1 - type_mismatch" do
    # Sabotage: emptied the tutorial phrase list - red, six tests, the
    # tutorial under the reference folder among them. Read fenced code as
    # prose - red, the fenced code test. Judged a page when its top type beat
    # the next once rather than twice - red, the mixed page test.
    test "a tutorial under the reference folder, at its H1", %{tmp_dir: dir} do
      result = run_in(dir, [{"docs/reference/first-total.md", @tutorial}])

      assert [finding] = Stage.findings(result)
      assert finding.check == "type_mismatch"
      assert finding.file == "docs/reference/first-total.md"
      assert finding.line == 1
      assert finding.severity == :warning

      assert finding.message =~
               "declared a reference page by its folder docs/reference, but reads as a tutorial"

      assert finding.message =~ ~r/tutorial \d+, how-to \d+, reference \d+, explanation \d+/
      assert result.status == :ok
      assert result.summary == "1 warning: type_mismatch at docs/reference/first-total.md:1"
    end

    test "an explanation under the tutorials folder", %{tmp_dir: dir} do
      result = run_in(dir, [{"docs/tutorials/integers.md", @explanation}])

      assert [{"type_mismatch", "docs/tutorials/integers.md", 1}] = checks(result)
      assert hd(Stage.findings(result)).message =~ "reads as an explanation"
    end

    test "a reference page under the explanation folder", %{tmp_dir: dir} do
      result = run_in(dir, [{"docs/explanation/options.md", @reference}])

      assert [{"type_mismatch", "docs/explanation/options.md", 1}] = checks(result)
      assert hd(Stage.findings(result)).message =~ "reads as a reference page"
    end

    test "a how-to guide under the explanation folder", %{tmp_dir: dir} do
      result = run_in(dir, [{"docs/explanation/limits.md", @how_to}])

      assert [{"type_mismatch", "docs/explanation/limits.md", 1}] = checks(result)
      assert hd(Stage.findings(result)).message =~ "reads as a how-to guide"
    end

    test "the finding sits at the H1 when the page has front matter", %{tmp_dir: dir} do
      page = "---\ntitle: First total\n---\n\n" <> @tutorial
      result = run_in(dir, [{"docs/reference/first-total.md", page}])

      assert [{"type_mismatch", "docs/reference/first-total.md", 5}] = checks(result)
    end

    test "a page whose cues are too few is not judged", %{tmp_dir: dir} do
      page = "# Totals\n\nA total is a sum.\n"
      result = run_in(dir, [{"docs/explanation/totals.md", page}])

      assert Stage.findings(result) == []
    end

    test "a page whose cues are mixed is not judged", %{tmp_dir: dir} do
      page = """
      # Totals

      In this tutorial, you will add numbers. The reason for it is that a sum
      matters, because totals are everywhere.
      """

      result = run_in(dir, [{"docs/reference/totals.md", page}])

      assert Stage.findings(result) == []
    end

    test "cues inside fenced code, inline code and link targets are not read", %{
      tmp_dir: dir
    } do
      page = """
      # Totals

      A total of `in this tutorial, you will` and a link to
      [the guide](in-this-tutorial-you-will-notice-that.md).

      ```
      In this tutorial, you will see.
      You should now see. Notice that. You will.
      ```
      """

      result = run_in(dir, [{"docs/reference/totals.md", page}])

      assert Stage.findings(result) == []
    end
  end

  describe "run/1 - the type key in a page's front matter" do
    test "overrides the folder's type", %{tmp_dir: dir} do
      page = "---\ntype: explanation\n---\n" <> @explanation
      result = run_in(dir, [{"docs/guides/integers.md", page}])

      # Declared an explanation, so neither a mismatch nor the How-to title rule.
      assert Stage.findings(result) == []
    end

    test "a declared type the page does not read as is a mismatch", %{tmp_dir: dir} do
      page = "---\ntype: \"how-to\"\n---\n" <> @reference
      result = run_in(dir, [{"docs/reference/options.md", page}])

      found = checks(result)
      assert {"type_mismatch", "docs/reference/options.md", 4} in found
      assert {"how_to_title", "docs/reference/options.md", 4} in found
      assert Enum.any?(Stage.findings(result), &(&1.message =~ "by its front matter"))
    end

    test "an unknown type is a finding, and the folder's type applies", %{tmp_dir: dir} do
      page = "---\ntype: recipe\n---\n" <> @reference
      result = run_in(dir, [{"docs/reference/options.md", page}])

      assert [finding] = Stage.findings(result)
      assert finding.check == "bad_type"
      assert finding.line == 2
      assert finding.message =~ ~s(type: "recipe")
    end
  end

  describe "run/1 - how_to_title" do
    # Sabotage: accepted every H1 as a How to title - red, the first test
    # here and the front matter how-to mismatch.
    test "a how-to guide whose H1 does not start with How to", %{tmp_dir: dir} do
      page = String.replace(@how_to, "# How to stop a total at a limit", "# Limits")
      result = run_in(dir, [{"docs/guides/limits.md", page}])

      assert [finding] = Stage.findings(result)
      assert finding.check == "how_to_title"
      assert finding.line == 1
      assert finding.message =~ ~s(this one is "Limits")
    end

    test "a how-to guide with no H1, at line 1", %{tmp_dir: dir} do
      page = String.replace(@how_to, "# How to stop a total at a limit\n", "")
      result = run_in(dir, [{"docs/guides/limits.md", page}])

      assert {"how_to_title", "docs/guides/limits.md", 1} in checks(result)
    end

    test "matches How to whatever its case", %{tmp_dir: dir} do
      page = String.replace(@how_to, "# How to", "# how to")
      result = run_in(dir, [{"docs/guides/limits.md", page}])

      assert Stage.findings(result) == []
    end

    test "only how-to guides carry the rule", %{tmp_dir: dir} do
      result = run_in(dir, [{"docs/reference/options.md", @reference}])

      assert Stage.findings(result) == []
    end
  end

  describe "run/1 - the manifest" do
    test "a repo without a manifest reports nothing", %{tmp_dir: dir} do
      result = run_in(dir, [{"docs/reference/first-total.md", @tutorial}], [], nil)

      assert result.status == :ok
      assert Stage.findings(result) == []
      assert result.summary == "no .claude/diataxis.md; no pages to read"
    end

    test "a quadrant whose folder does not exist has no pages", %{tmp_dir: dir} do
      result = run_in(dir, [{"docs/guides/limits.md", @how_to}])

      assert result.summary == "1 page, each reads as its type"
    end

    test "reads quoted paths, trailing comments and CRLF line endings", %{tmp_dir: dir} do
      manifest =
        "---\r\nquadrants: # the four\r\n  tutorials: \"docs/learn\" # quoted\r\n" <>
          "  how_to: 'docs/do'\r\n  reference: docs/look # bare\r\n---\r\n"

      pages = [{"docs/look/first-total.md", @tutorial}, {"docs/do/limits.md", @how_to}]
      result = run_in(dir, pages, [], manifest)

      assert [{"type_mismatch", "docs/look/first-total.md", 1}] = checks(result)
      assert result.summary =~ "1 warning"
    end

    test "a page under two quadrant paths belongs to the deeper one", %{tmp_dir: dir} do
      manifest = "---\nquadrants:\n  reference: docs\n  how_to: docs/guides\n---\n"
      pages = [{"docs/guides/limits.md", @how_to}, {"docs/options.md", @reference}]
      result = run_in(dir, pages, [], manifest)

      assert Stage.findings(result) == []
      assert result.summary == "2 pages, each reads as its type"
    end

    test "front matter that never closes", %{tmp_dir: dir} do
      result = run_in(dir, [], [], "---\nquadrants:\n  how_to: docs/guides\n")

      assert [{"bad_manifest", ".claude/diataxis.md", 1}] = checks(result)
    end

    test "no quadrants map", %{tmp_dir: dir} do
      result = run_in(dir, [{"docs/guides/limits.md", @tutorial}], [], "---\nreadme: x\n---\n")

      assert [finding] = Stage.findings(result)
      assert finding.check == "bad_manifest"
      assert finding.message =~ "no quadrants: map"
    end

    test "no front matter at all", %{tmp_dir: dir} do
      result = run_in(dir, [], [], "quadrants:\n  how_to: docs/guides\n")

      assert [{"bad_manifest", ".claude/diataxis.md", 1}] = checks(result)
    end
  end

  describe "run/1 - severity" do
    test "warnings by default: the stage passes", %{tmp_dir: dir} do
      result = run_in(dir, [{"docs/reference/first-total.md", @tutorial}])

      assert result.status == :ok
      assert [%{severity: :warning}] = Stage.findings(result)
    end

    test "severity: :error fails the stage on any finding", %{tmp_dir: dir} do
      result =
        run_in(dir, [{"docs/reference/first-total.md", @tutorial}], diataxis: [severity: :error])

      assert result.status == :error
      assert [%{severity: :error}] = Stage.findings(result)
      assert result.summary == "1 problem"
    end

    test "severity: :error passes a clean tree", %{tmp_dir: dir} do
      assert run_in(dir, one_page_per_type(), diataxis: [severity: :error]).status == :ok
    end

    test "an unknown severity fails the stage and says what it accepts", %{tmp_dir: dir} do
      result = run_in(dir, one_page_per_type(), diataxis: [severity: :fatal])

      assert result.status == :error
      assert result.summary =~ "must be :warning or :error, got: :fatal"
    end
  end
end
