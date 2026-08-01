defmodule ExQuality.FindingTest do
  use ExUnit.Case, async: true

  alias ExQuality.Finding

  doctest ExQuality.Finding

  defp finding(attrs) do
    struct!(%Finding{file: "lib/a.ex", message: "boom"}, attrs)
  end

  describe "sort/1" do
    test "orders by file, then line, then column" do
      findings = [
        finding(file: "lib/b.ex", line: 1, message: "fourth"),
        finding(file: "lib/a.ex", line: 9, message: "third"),
        finding(file: "lib/a.ex", line: 2, column: 8, message: "second"),
        finding(file: "lib/a.ex", line: 2, column: 1, message: "first")
      ]

      assert Enum.map(Finding.sort(findings), & &1.message) ==
               ["first", "second", "third", "fourth"]
    end

    test "sorts findings without a line before those with one" do
      findings = [
        finding(line: 3, message: "located"),
        finding(line: nil, message: "file-level")
      ]

      assert Enum.map(Finding.sort(findings), & &1.message) == ["file-level", "located"]
    end
  end

  describe "group_by_file/1" do
    test "returns one entry per file in sorted order" do
      findings = [
        finding(file: "lib/b.ex", line: 1),
        finding(file: "lib/a.ex", line: 2),
        finding(file: "lib/a.ex", line: 1)
      ]

      assert [{"lib/a.ex", a_findings}, {"lib/b.ex", b_findings}] =
               Finding.group_by_file(findings)

      assert Enum.map(a_findings, & &1.line) == [1, 2]
      assert length(b_findings) == 1
    end

    test "returns an empty list for no findings" do
      assert Finding.group_by_file([]) == []
    end
  end

  describe "group_by_app/1" do
    test "returns one entry per app in sorted order" do
      findings = [
        finding(file: "apps/b/lib/b.ex", app: :b),
        finding(file: "apps/a/lib/a.ex", app: :a, line: 2),
        finding(file: "apps/a/lib/a.ex", app: :a, line: 1)
      ]

      assert [{:a, a_findings}, {:b, b_findings}] = Finding.group_by_app(findings)

      assert Enum.map(a_findings, & &1.line) == [1, 2]
      assert length(b_findings) == 1
    end

    test "puts findings with no app first, in one group" do
      findings = [
        finding(file: "apps/a/lib/a.ex", app: :a),
        finding(file: "lib/root.ex"),
        finding(file: "mix.exs")
      ]

      assert [{nil, rootless}, {:a, _app_findings}] = Finding.group_by_app(findings)
      assert Enum.map(rootless, & &1.file) == ["lib/root.ex", "mix.exs"]
    end

    test "returns an empty list for no findings" do
      assert Finding.group_by_app([]) == []
    end
  end

  describe "render/1" do
    test "returns an empty string for no findings" do
      assert Finding.render([]) == ""
    end

    test "groups findings under their file with aligned positions" do
      findings = [
        finding(file: "lib/a.ex", line: 5, column: 3, message: "short", check: "readability"),
        finding(file: "lib/a.ex", line: 100, column: 12, message: "long", check: "design")
      ]

      assert Finding.render(findings) ==
               "lib/a.ex\n" <>
                 "  5:3     [warning] short (readability)\n" <>
                 "  100:12  [warning] long (design)\n"
    end

    test "separates file groups with a blank line" do
      findings = [finding(file: "lib/a.ex", line: 1), finding(file: "lib/b.ex", line: 1)]

      assert Finding.render(findings) =~ "\n\nlib/b.ex\n"
    end

    test "omits the check when the stage did not supply one" do
      assert Finding.render([finding(line: 1, check: nil)]) =~ "[warning] boom\n"
    end

    test "renders a finding without a position" do
      assert Finding.render([finding(line: nil)]) =~ "  -  [warning] boom"
    end

    test "shows the severity the stage assigned" do
      assert Finding.render([finding(line: 1, severity: :error)]) =~ "[error]"
      assert Finding.render([finding(line: 1, severity: :info)]) =~ "[info]"
    end

    test "groups by app under a header when findings name one" do
      findings = [
        finding(file: "apps/b/lib/b.ex", app: :b, line: 1, check: nil),
        finding(file: "apps/a/lib/a.ex", app: :a, line: 1, check: nil)
      ]

      assert Finding.render(findings) ==
               "── a ──\n" <>
                 "apps/a/lib/a.ex\n" <>
                 "  1  [warning] boom\n" <>
                 "\n" <>
                 "── b ──\n" <>
                 "apps/b/lib/b.ex\n" <>
                 "  1  [warning] boom\n"
    end

    test "renders findings with no app without a header" do
      findings = [
        finding(file: "apps/a/lib/a.ex", app: :a, line: 1, check: nil),
        finding(file: "lib/root.ex", line: 1, check: nil)
      ]

      rendered = Finding.render(findings)

      assert rendered =~ "lib/root.ex\n  1  [warning] boom\n"
      assert rendered =~ "── a ──"
      # The app-less group leads, so no header precedes the root file.
      assert String.starts_with?(rendered, "lib/root.ex\n")
    end

    test "adds no header when no finding names an app" do
      refute Finding.render([finding(line: 1)]) =~ "──"
    end
  end
end
