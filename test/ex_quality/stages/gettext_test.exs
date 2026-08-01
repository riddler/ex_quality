defmodule ExQuality.Stages.GettextTest do
  # Not async: the stage reads `.po` files relative to the working directory,
  # so each test runs from a tree of its own.
  use ExUnit.Case, async: false
  use Mimic

  alias ExQuality.Stage
  alias ExQuality.Stages.Gettext

  @untranslated """
  msgid ""
  msgstr ""
  "Language: fr\\n"

  #: lib/web/page.ex:12
  msgid "Hello"
  msgstr ""
  """

  @translated """
  msgid ""
  msgstr ""
  "Language: fr\\n"

  #: lib/web/page.ex:12
  msgid "Hello"
  msgstr "Bonjour"
  """

  @fuzzy """
  msgid ""
  msgstr ""
  "Language: fr\\n"

  #, fuzzy
  msgid "Goodbye"
  msgstr "Au revoir"
  """

  # Each test describes the tree it wants as `path => contents` and is run from
  # inside it, because the stage's whole job is finding files from the root.
  defp in_project(files, fun) do
    root =
      Path.join(System.tmp_dir!(), "ex_quality-gettext-#{System.unique_integer([:positive])}")

    Enum.each(files, fn {path, contents} ->
      full = Path.join(root, path)
      File.mkdir_p!(Path.dirname(full))
      File.write!(full, contents)
    end)

    File.mkdir_p!(root)
    cwd = File.cwd!()

    try do
      File.cd!(root, fun)
    after
      File.cd!(cwd)
      File.rm_rf!(root)
    end
  end

  defp stub_umbrella(apps) do
    stub(ExQuality.Umbrella, :apps_paths, fn -> apps end)
  end

  describe "stage_kind/1" do
    test "reads by default" do
      assert Gettext.stage_kind([]) == :reader
    end

    test "writes when configured to extract" do
      assert Gettext.stage_kind(gettext: [extract: true]) == :writer
    end
  end

  describe "run/1 - umbrella" do
    setup do
      stub_umbrella(%{core: "apps/core", web: "apps/web"})
      :ok
    end

    test "finds .po files under the child apps and names the app" do
      files = %{
        "apps/web/priv/gettext/fr/LC_MESSAGES/default.po" => @untranslated,
        "apps/core/priv/gettext/fr/LC_MESSAGES/default.po" => @translated
      }

      in_project(files, fn ->
        result = Gettext.run([])

        assert result.status == :error
        assert [finding] = Stage.findings(result)
        assert finding.app == :web
        assert finding.file == "apps/web/priv/gettext/fr/LC_MESSAGES/default.po"
        assert finding.line == 6
        assert finding.check == "missing"
        assert finding.message == ~s(missing translation for "Hello")
      end)
    end

    test "counts every app's files, not just the first" do
      files = %{
        "apps/web/priv/gettext/fr/LC_MESSAGES/default.po" => @translated,
        "apps/core/priv/gettext/fr/LC_MESSAGES/default.po" => @translated
      }

      in_project(files, fn ->
        result = Gettext.run([])

        assert result.status == :ok
        assert result.stats.file_count == 2
        assert result.summary == "All translations complete (2 files)"
      end)
    end
  end

  describe "run/1 - nothing to read" do
    setup do
      stub_umbrella(%{})
      :ok
    end

    test "skips rather than passes when there are no .po files at all" do
      in_project(%{"mix.exs" => ""}, fn ->
        result = Gettext.run([])

        assert result.status == :skipped
        assert result.summary == "no .po files found"
      end)
    end

    test "skips when the only locale is the source locale" do
      in_project(%{"priv/gettext/en/LC_MESSAGES/default.po" => @untranslated}, fn ->
        result = Gettext.run([])

        assert result.status == :skipped
        assert result.summary == "no .po files outside the source locale"
      end)
    end

    test "skips when every file was excluded by name" do
      in_project(%{"priv/gettext/fr/LC_MESSAGES/errors.po" => @untranslated}, fn ->
        result = Gettext.run([])

        assert result.status == :skipped
        assert result.summary == "no .po files outside the source locale"
      end)
    end
  end

  describe "run/1 - configuration" do
    setup do
      stub_umbrella(%{})
      :ok
    end

    test "the source locale is configurable" do
      files = %{
        "priv/gettext/en/LC_MESSAGES/default.po" => @untranslated,
        "priv/gettext/fr/LC_MESSAGES/default.po" => @translated
      }

      in_project(files, fn ->
        result = Gettext.run(gettext: [source_locale: "fr"])

        assert result.status == :error
        assert [%{file: "priv/gettext/en/LC_MESSAGES/default.po"}] = Stage.findings(result)
      end)
    end

    test "the excluded basenames are configurable" do
      in_project(%{"priv/gettext/fr/LC_MESSAGES/errors.po" => @untranslated}, fn ->
        result = Gettext.run(gettext: [exclude: []])

        assert result.status == :error
        assert [%{check: "missing"}] = Stage.findings(result)
      end)
    end
  end

  describe "run/1 - fuzzy translations" do
    setup do
      stub_umbrella(%{})
      :ok
    end

    test "reports a fuzzy entry at its msgid" do
      in_project(%{"priv/gettext/fr/LC_MESSAGES/default.po" => @fuzzy}, fn ->
        result = Gettext.run([])

        assert result.status == :error
        assert [finding] = Stage.findings(result)
        assert finding.check == "fuzzy"
        assert finding.line == 6
        assert result.summary == "1 fuzzy translation"
      end)
    end
  end

  describe "run/1 - extraction" do
    setup do
      stub_umbrella(%{})
      :ok
    end

    test "does not run extraction, or write anything, by default" do
      System
      |> reject(:cmd, 3)

      files = %{"priv/gettext/fr/LC_MESSAGES/default.po" => @translated}

      in_project(files, fn ->
        before = snapshot()
        assert Gettext.run([]).status == :ok
        assert snapshot() == before
      end)
    end

    test "runs extraction when asked" do
      System
      |> expect(:cmd, fn "mix", ["gettext.extract", "--merge"], _opts -> {"Extracted", 0} end)

      files = %{"priv/gettext/fr/LC_MESSAGES/default.po" => @translated}

      in_project(files, fn ->
        assert Gettext.run(gettext: [extract: true]).status == :ok
      end)
    end

    test "fails when extraction fails" do
      System
      |> expect(:cmd, fn "mix", ["gettext.extract", "--merge"], _opts -> {"boom", 1} end)

      in_project(%{}, fn ->
        result = Gettext.run(gettext: [extract: true])

        assert result.status == :error
        assert result.summary == "Extraction failed"
      end)
    end
  end

  describe "run/1 - timing" do
    setup do
      stub_umbrella(%{})
      :ok
    end

    test "records execution duration" do
      in_project(%{"priv/gettext/fr/LC_MESSAGES/default.po" => @translated}, fn ->
        result = Gettext.run([])

        assert is_integer(result.duration_ms)
        assert result.duration_ms >= 0
        assert result.duration_ms < 5_000
      end)
    end
  end

  # Every file's path and mtime: what a check that must not touch the tree is
  # measured against.
  defp snapshot do
    "**/*"
    |> Path.wildcard(match_dot: true)
    |> Enum.map(&{&1, File.stat!(&1).mtime})
    |> Enum.sort()
  end
end
