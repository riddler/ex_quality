defmodule ExQuality.Stages.DocsTest do
  use ExUnit.Case, async: true
  use Mimic

  alias ExQuality.Stage
  alias ExQuality.Stages.Docs

  describe "run/1 - zero warnings" do
    test "returns success" do
      System
      |> expect(:cmd, fn "mix", ["docs", "--formatter", "html", "--output", _out], _opts ->
        {"Generating docs...\nView \"html\" docs at \"doc/index.html\"\n", 0}
      end)

      result = Docs.run([])

      assert result.name == "Docs"
      assert result.status == :ok
      assert result.summary == "No warnings"
      assert result.stats == %{warning_count: 0}
      assert is_integer(result.duration_ms)
    end
  end

  describe "run/1 - warnings" do
    test "fails with one finding per warning at the reported file:line" do
      output = """
      Generating docs...
      warning: documentation references function ExQuality.Foo.bar/1 but it is undefined or private
        lib/ex_quality/foo.ex:15: ExQuality.Foo

      warning: documentation references module ExQuality.Missing but it is undefined
        README.md:12

      View "html" docs at "doc/index.html"
      """

      System
      |> expect(:cmd, fn "mix", ["docs" | _rest], _opts -> {output, 0} end)

      result = Docs.run([])

      assert result.status == :error
      assert result.summary == "2 warnings"
      assert result.stats == %{warning_count: 2}

      assert [readme, foo] = Stage.findings(result)

      assert readme.file == "README.md"
      assert readme.line == 12
      assert readme.severity == :error
      assert readme.check == "ex_doc"
      assert readme.message =~ "references module ExQuality.Missing"

      assert foo.file == "lib/ex_quality/foo.ex"
      assert foo.line == 15
      assert foo.message =~ "undefined or private"
      assert foo.raw =~ "lib/ex_quality/foo.ex:15"
    end

    test "uses the singular for one warning" do
      output = """
      warning: documentation references module Nope but it is undefined
        lib/a.ex:1: A
      """

      System
      |> expect(:cmd, fn "mix", ["docs" | _rest], _opts -> {output, 0} end)

      assert Docs.run([]).summary == "1 warning"
    end

    test "warnings fail the stage even when mix docs exits 0" do
      System
      |> expect(:cmd, fn "mix", ["docs" | _rest], _opts ->
        {"warning: invalid link\n  lib/a.ex:3: A\n", 0}
      end)

      assert Docs.run([]).status == :error
    end

    test "warnings are still counted when mix docs exits non-zero" do
      System
      |> expect(:cmd, fn "mix", ["docs" | _rest], _opts ->
        {"warning: invalid link\n  lib/a.ex:3: A\n", 1}
      end)

      result = Docs.run([])

      assert result.status == :error
      assert result.summary == "1 warning"
    end
  end

  describe "run/1 - warnings without a location" do
    test "falls back to output verbatim rather than dropping the warning" do
      output = """
      warning: this warning names no file at all
      warning: documentation references module Nope but it is undefined
        lib/a.ex:1: A
      """

      System
      |> expect(:cmd, fn "mix", ["docs" | _rest], _opts -> {output, 0} end)

      result = Docs.run([])

      assert result.status == :error
      assert result.summary == "2 warnings"
      assert Stage.findings(result) == []
      assert result.output == output
    end
  end

  describe "run/1 - tool failure" do
    test "a mix docs that fails without warnings is an error, not a pass" do
      System
      |> expect(:cmd, fn "mix", ["docs" | _rest], _opts ->
        {"** (Mix) The task \"docs\" could not be found\n", 1}
      end)

      result = Docs.run([])

      assert result.status == :error
      assert result.summary == "mix docs failed (see output)"
      assert result.output =~ "could not be found"
    end
  end

  describe "run/1 - invocation" do
    test "builds one formatter into a temporary output directory" do
      System
      |> expect(:cmd, fn "mix", ["docs", "--formatter", "html", "--output", out], opts ->
        assert String.starts_with?(out, System.tmp_dir!())
        assert {"MIX_ENV", "dev"} in Keyword.fetch!(opts, :env)
        assert Keyword.fetch!(opts, :stderr_to_stdout)
        {"", 0}
      end)

      assert Docs.run([]).status == :ok
    end
  end
end
