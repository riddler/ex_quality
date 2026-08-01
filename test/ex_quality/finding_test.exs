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

  describe "from_map/2" do
    test "reads every field a tool reports" do
      {:ok, parsed} =
        Finding.from_map(%{
          "file" => "lib/user.ex",
          "line" => 14,
          "column" => 3,
          "app" => "ex_quality",
          "severity" => "error",
          "check" => "unsound",
          "message" => "typed non-nil over a nullable column"
        })

      assert %Finding{
               file: "lib/user.ex",
               line: 14,
               column: 3,
               app: :ex_quality,
               severity: :error,
               check: "unsound",
               message: "typed non-nil over a nullable column"
             } = parsed
    end

    test "requires only a file and a message" do
      assert {:ok, parsed} = Finding.from_map(%{"file" => "lib/a.ex", "message" => "no"})

      assert %Finding{line: nil, column: nil, app: nil, check: nil, severity: :warning} = parsed
    end

    test "rejects an entry with nowhere to look" do
      assert Finding.from_map(%{"message" => "no file"}) == :error
      assert Finding.from_map(%{"file" => "lib/a.ex"}) == :error
      assert Finding.from_map(%{"file" => 1, "message" => "no"}) == :error
    end

    test "reads each severity, and defaults an unknown one rather than dropping it" do
      for {given, expected} <- [{"error", :error}, {"warning", :warning}, {"info", :info}] do
        assert {:ok, %{severity: ^expected}} =
                 Finding.from_map(%{"file" => "a.ex", "message" => "x", "severity" => given})
      end

      assert {:ok, %{severity: :warning}} =
               Finding.from_map(%{"file" => "a.ex", "message" => "x", "severity" => "critical"})
    end

    test "ignores a line or column that is not a position" do
      assert {:ok, %{line: nil, column: nil}} =
               Finding.from_map(%{
                 "file" => "a.ex",
                 "message" => "x",
                 "line" => 0,
                 "column" => "3"
               })
    end

    test "infers the app from the path when the tool does not name one" do
      assert {:ok, %{app: :web}} =
               Finding.from_map(
                 %{"file" => "apps/web/lib/user.ex", "message" => "x"},
                 %{web: "apps/web"}
               )
    end

    test "ignores an app ex_quality has never heard of" do
      assert {:ok, %{app: nil}} =
               Finding.from_map(%{
                 "file" => "a.ex",
                 "message" => "x",
                 "app" => "no_such_app_here"
               })
    end

    test "normalises an absolute path against the run's root" do
      absolute = Path.join(File.cwd!(), "lib/user.ex")

      assert {:ok, %{file: "lib/user.ex"}} =
               Finding.from_map(%{"file" => absolute, "message" => "x"})
    end

    test "keeps the object each finding came from" do
      {:ok, parsed} = Finding.from_map(%{"file" => "lib/a.ex", "message" => "no"})

      assert parsed.raw =~ "lib/a.ex"
    end
  end
end
