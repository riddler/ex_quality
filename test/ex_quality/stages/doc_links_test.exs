defmodule ExQuality.Stages.DocLinksTest do
  # Each test loads a fixture project with `Mix.Project.in_project/3`, which
  # changes the working directory and the current Mix project: both are
  # global, so this module cannot run alongside the others.
  use ExUnit.Case, async: false

  alias ExQuality.Stage
  alias ExQuality.Stages.DocLinks

  @fixtures Path.expand("../../../fixtures/doc_links", __DIR__)

  defp run_fixture(app, dir) do
    Mix.Project.in_project(app, Path.join(@fixtures, dir), fn _module -> DocLinks.run([]) end)
  end

  defp by_check(result, check), do: Enum.filter(Stage.findings(result), &(&1.check == check))

  defp locations(findings), do: Enum.map(findings, &{&1.file, &1.line})

  describe "run/1 - a project that keeps every rule" do
    # Sabotage: made `relative_path/1` return an anchor-only target instead of
    # nil - red, the README's `#licence` link became a finding. Made it skip
    # stripping the anchor and query - red, `holds.md?q=1#top` no longer
    # resolved to an extra. Made `fence?/1` always false - red, the fenced
    # `[copy](missing.md)` became a `not_an_extra` finding.
    test "passes, and the scan saw every link the fixture carries" do
      result = run_fixture(:doc_links_clean, "clean")

      assert result.name == "Doc links"
      assert result.status == :ok
      assert Stage.findings(result) == []

      # Anti-vacuity floor: the fixture carries ten links a reader would
      # follow (five in the README counting its images, three in holds.md,
      # one each in loans.md and branches.md). A scan that silently matched
      # nothing would pass the assertions above.
      assert result.stats.link_count >= 10
      assert result.stats.finding_count == 0
      assert result.summary == "#{result.stats.link_count} links checked"
      assert is_integer(result.duration_ms)
    end
  end

  describe "run/1 - (a) a README link the package does not ship" do
    # Sabotage: made `packaged?/2` return true for every path - red, both
    # README findings disappeared.
    test "fails at the README line for a link and for an image" do
      result = run_fixture(:doc_links_broken, "broken")

      assert result.status == :error
      findings = by_check(result, "readme_not_packaged")

      assert locations(findings) == [{"README.md", 3}, {"README.md", 5}]
      assert Enum.all?(findings, &(&1.severity == :error))
      assert hd(findings).message =~ "links to docs/holds.md, which the package does not ship"
      assert List.last(findings).message =~ "links to assets/branch.svg"
    end
  end

  describe "run/1 - (a) Hex's default file list when package names no files" do
    # Sabotage: made `package_files/1` return `[]` when `files:` is absent -
    # red, CHANGELOG.md, LICENSE and mix.exs were reported as unshipped too.
    # Then made it return `["**"]` - red, docs/holds.md was no longer reported.
    test "checks against the default list rather than reporting nothing" do
      result = run_fixture(:doc_links_hex_default, "hex_default_files")

      # Anti-vacuity floor: the README carries four relative links.
      assert result.stats.link_count >= 4

      # CHANGELOG*, LICENSE* and mix.exs are in Hex's default list; docs/ is not.
      assert locations(Stage.findings(result)) == [{"README.md", 4}]
      assert [finding] = by_check(result, "readme_not_packaged")
      assert finding.message =~ "docs/holds.md"
    end
  end

  describe "run/1 - (b) a link in an extra to a file that is not an extra" do
    # Sabotage: made the arm before `not_an_extra` in `link_findings/4` match
    # every link (`true ->`) - red, neither finding appeared (and the
    # zero-arity test below went red with it).
    test "fails at the extra's line, resolving the target from the linking file" do
      result = run_fixture(:doc_links_broken, "broken")
      findings = by_check(result, "not_an_extra")

      assert locations(findings) == [{"docs/holds.md", 5}, {"docs/holds.md", 7}]
      assert Enum.at(findings, 0).message =~ "links to CONTRIBUTING.md, which is not in extras"
      assert Enum.at(findings, 1).message =~ "links to docs/adr/0001-holds.md"

      # Anti-vacuity floor: README.md and docs/holds.md carry five links.
      assert result.stats.link_count >= 5
      assert result.stats.finding_count == length(Stage.findings(result))
      assert result.summary == "#{result.stats.finding_count} problems"
      assert result.output =~ "docs/holds.md:5: links to CONTRIBUTING.md"
    end
  end

  describe "run/1 - (c) two extras sharing a basename" do
    # Sabotage: dropped the `is_nil(extra.filename)` guard in
    # `duplicate_findings/2` - red, docs/branches/README.md was reported as
    # well. Then made it return `[]` - red, no finding at all.
    test "fails at the second extra's mix.exs line unless it carries filename:" do
      result = run_fixture(:doc_links_duplicates, "duplicates")

      assert result.status == :error
      assert [finding] = Stage.findings(result)
      assert finding.check == "duplicate_extra"
      assert {finding.file, finding.line} == {"mix.exs", 26}
      assert finding.message =~ "README.md and docs/adr/README.md share the basename README.md"
      assert result.summary == "1 problem"
    end
  end

  describe "run/1 - (d) a link ExDoc rewrites to a different extra" do
    # Sabotage: made `rewritten_to/2` return nil - red, the link fell through to
    # `not_an_extra` instead, which hides that HexDocs sends the reader to the
    # package's front page rather than answering 404.
    test "fails naming the extra the link lands on" do
      result = run_fixture(:doc_links_broken, "broken")

      assert [finding] = by_check(result, "rewritten_to_other_extra")
      assert {finding.file, finding.line} == {"docs/holds.md", 9}

      assert finding.message =~
               "links to docs/adr/README.md, which ExDoc rewrites to the extra README.md"
    end
  end

  describe "run/1 - a zero-arity docs config" do
    # Sabotage: made `docs_config/1` treat a function as `[]` - red, no extras
    # were read, so the finding and the link count both went to the README's.
    test "is called and its extras are read" do
      result = run_fixture(:doc_links_function_docs, "function_docs")

      # Anti-vacuity floor: README.md and docs/parcels.md carry two links.
      assert result.stats.link_count >= 2
      assert [finding] = Stage.findings(result)
      assert finding.check == "not_an_extra"
      assert {finding.file, finding.line} == {"docs/parcels.md", 4}
    end
  end
end
