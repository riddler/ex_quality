defmodule ExQuality.Stages.DocsTest do
  use ExUnit.Case, async: true
  use Mimic

  alias ExQuality.Stage
  alias ExQuality.Stages.Docs

  describe "run/1 - zero warnings" do
    test "returns success" do
      System
      |> expect(:cmd, fn "mix",
                         ["docs", "--formatter", "html", "--output", _out, "--warnings-as-errors"],
                         _opts ->
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

  # The shape ExDoc 0.40 prints on Elixir 1.18: the warning line is indented,
  # a source excerpt follows, and the location closes the block on a `└─`
  # line. Captured from a real `mix docs` run; the width of the indent follows
  # the width of the line number, so both a four- and a five-space indent
  # appear. `mix docs` exits 0 over all of it.
  @diagnostic_output """
  Generating docs...
       warning: documentation references function "MyApp.Envelope.ref/2" but it is undefined or private
       │
   118 │ Elixir names the changelog lists, such as `MyApp.Envelope.ref/2`,
       │ ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
       │
       └─ README.md:118: (file)

       warning: documentation references module "MyApp.Hidden" but it is hidden
       │
   479 │ (`MyApp.Hidden`). Under a shared store the node's table
       │ ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
       │
       └─ guides/runbook.md:479: (file)

      warning: documentation references function "MyApp.nosuch/1" but it is undefined or private
      │
    3 │   See `MyApp.nosuch/1` and the guides.
      │   ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
      │
      └─ lib/my_app.ex:3: MyApp (module)

  View "html" docs at "doc/index.html"
  """

  describe "run/1 - the Elixir 1.18 diagnostic shape" do
    test "fails on indented warnings even when mix docs exits 0" do
      System
      |> expect(:cmd, fn "mix", ["docs" | _rest], _opts -> {@diagnostic_output, 0} end)

      result = Docs.run([])

      assert result.status == :error
      assert result.summary == "3 warnings"
      assert result.stats == %{warning_count: 3}
    end

    test "each warning is a finding at the file:line on its location line" do
      System
      |> expect(:cmd, fn "mix", ["docs" | _rest], _opts -> {@diagnostic_output, 0} end)

      assert [readme, runbook, lib] = Stage.findings(Docs.run([]))

      assert {readme.file, readme.line} == {"README.md", 118}
      assert {runbook.file, runbook.line} == {"guides/runbook.md", 479}
      assert {lib.file, lib.line} == {"lib/my_app.ex", 3}

      assert readme.check == "ex_doc"
      assert readme.severity == :error

      assert readme.message ==
               ~s(documentation references function "MyApp.Envelope.ref/2" but it is undefined or private)

      assert lib.message ==
               ~s(documentation references function "MyApp.nosuch/1" but it is undefined or private)

      assert runbook.raw =~ "└─ guides/runbook.md:479: (file)"
    end

    test "a location line with no line number falls back to output verbatim" do
      output = """
          warning: documentation references file "missing.md" but it does not exist
          │
          └─ lib/my_app.ex: MyApp (module)
      """

      System
      |> expect(:cmd, fn "mix", ["docs" | _rest], _opts -> {output, 0} end)

      result = Docs.run([])

      assert result.status == :error
      assert result.summary == "1 warning"
      assert Stage.findings(result) == []
      assert result.output == output
    end
  end

  describe "run/1 - warnings as errors" do
    test "a non-zero exit over warnings the parse misses is an error naming them" do
      output = """
      Generating docs...
      a warning in some shape this stage does not know
      Documents have been generated, but generation for html format failed due to warnings while using the --warnings-as-errors option
      """

      System
      |> expect(:cmd, fn "mix", ["docs" | _rest], _opts -> {output, 1} end)

      result = Docs.run([])

      assert result.status == :error
      assert result.summary == "ExDoc reported warnings (see output)"
      assert result.output == output
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
    test "builds one formatter into a temporary output directory, warnings as errors" do
      System
      |> expect(:cmd, fn "mix",
                         ["docs", "--formatter", "html", "--output", out, "--warnings-as-errors"],
                         opts ->
        assert String.starts_with?(out, System.tmp_dir!())
        assert {"MIX_ENV", "dev"} in Keyword.fetch!(opts, :env)
        assert Keyword.fetch!(opts, :stderr_to_stdout)
        {"", 0}
      end)

      assert Docs.run([]).status == :ok
    end
  end
end
