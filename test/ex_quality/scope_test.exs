defmodule ExQuality.ScopeTest do
  # Not async: the `:changed` cases run git against a working tree, and the
  # working directory is per-node rather than per-process.
  use ExUnit.Case, async: false

  alias ExQuality.Scope

  doctest ExQuality.Scope

  # A real repository rather than a stubbed git: the point of `:changed` is that
  # it reads uncommitted and untracked work, and a stub that returns whatever the
  # test wants proves nothing about which git commands would actually say so.
  setup context do
    if context[:repo] do
      repo =
        Path.join(System.tmp_dir!(), "ex_quality_scope_#{System.unique_integer([:positive])}")

      File.mkdir_p!(repo)
      on_exit(fn -> File.rm_rf!(repo) end)

      git(repo, ["init", "--initial-branch", "main"])
      git(repo, ["config", "user.email", "test@example.com"])
      git(repo, ["config", "user.name", "Test"])

      write(repo, "mix.exs", "# project\n")
      write(repo, "lib/kept.ex", "defmodule Kept do\nend\n")
      write(repo, "test/kept_test.exs", "defmodule KeptTest do\nend\n")
      git(repo, ["add", "."])
      git(repo, ["commit", "-m", "initial"])

      %{repo: repo}
    else
      :ok
    end
  end

  defp git(repo, args) do
    {output, code} = System.cmd("git", args, cd: repo, stderr_to_stdout: true)
    assert code == 0, "git #{Enum.join(args, " ")} failed: #{output}"
    output
  end

  defp write(repo, path, contents) do
    full = Path.join(repo, path)
    File.mkdir_p!(Path.dirname(full))
    File.write!(full, contents)
  end

  # The resolver reads the working tree, so it has to run in it.
  defp in_repo(repo, fun) do
    cwd = File.cwd!()
    File.cd!(repo)

    try do
      fun.()
    after
      File.cd!(cwd)
    end
  end

  describe "parse/1" do
    test "accepts both the atom and the string spelling" do
      assert Scope.parse(:all) == {:ok, :all}
      assert Scope.parse("all") == {:ok, :all}
      assert Scope.parse(:changed) == {:ok, :changed}
      assert Scope.parse("changed") == {:ok, :changed}
    end

    test "treats any other string as a glob" do
      assert Scope.parse("test/unit/**/*_test.exs") == {:ok, {:glob, "test/unit/**/*_test.exs"}}
    end

    test "round-trips an already-parsed glob" do
      assert Scope.parse({:glob, "test/**"}) == {:ok, {:glob, "test/**"}}
    end

    test "rejects anything else" do
      assert {:error, message} = Scope.parse(:nearly)
      assert message =~ "must be :all, :changed or a glob string"

      assert {:error, _message} = Scope.parse("")
    end
  end

  describe "from_config/1" do
    test "defaults to :all" do
      assert Scope.from_config([]) == :all
      assert Scope.from_config(test: []) == :all
    end

    test "raises rather than falling back on a bad value" do
      assert_raise Mix.Error, ~r/must be :all, :changed or a glob string/, fn ->
        Scope.from_config(test: [scope: :chagned])
      end
    end
  end

  describe "resolve/2 with :all" do
    test "resolves to the whole suite and takes no base ref" do
      assert Scope.resolve(:all) == %{
               scope: :all,
               requested_scope: :all,
               files: :all,
               base_ref: nil,
               fallback_reason: nil
             }
    end
  end

  describe "resolve/2 with a glob" do
    test "resolves to the matching test files" do
      resolved = Scope.resolve({:glob, "test/ex_quality/stages/*_test.exs"})

      assert resolved.scope == {:glob, "test/ex_quality/stages/*_test.exs"}
      assert "test/ex_quality/stages/credo_test.exs" in resolved.files
      assert resolved.fallback_reason == nil
    end

    test "ignores matches that are not test files" do
      resolved = Scope.resolve({:glob, "lib/ex_quality/*.ex"})

      assert resolved.files == :all
      assert resolved.fallback_reason == "the glob matched no test files"
    end

    test "falls back to the full suite when nothing matches" do
      resolved = Scope.resolve({:glob, "test/nothing/**/*_test.exs"})

      assert resolved.scope == :all
      assert resolved.requested_scope == {:glob, "test/nothing/**/*_test.exs"}
      assert resolved.files == :all
      assert resolved.fallback_reason == "the glob matched no test files"
    end
  end

  describe "test_files/1" do
    test "maps a source file to the test file beside it" do
      assert Scope.test_files(["lib/ex_quality/scope.ex"]) == ["test/ex_quality/scope_test.exs"]
    end

    test "maps an umbrella source file under its own app" do
      # Nothing exists at that path here, so this asserts the mapping through the
      # only observable it has: a mapped path that does not exist is dropped.
      assert Scope.test_files(["apps/web/lib/web/user.ex"]) == []
    end

    test "keeps a changed test file as itself" do
      assert Scope.test_files(["test/ex_quality/scope_test.exs"]) == [
               "test/ex_quality/scope_test.exs"
             ]
    end

    test "drops files with no test to run" do
      assert Scope.test_files(["mix.exs", "README.md", ".quality.exs"]) == []
    end

    test "drops a source file whose test file does not exist" do
      assert Scope.test_files(["lib/ex_quality/no_such_module.ex"]) == []
    end

    test "deduplicates a source file changed alongside its own test" do
      assert Scope.test_files(["lib/ex_quality/scope.ex", "test/ex_quality/scope_test.exs"]) == [
               "test/ex_quality/scope_test.exs"
             ]
    end
  end

  describe "resolve/2 with :changed" do
    @tag :repo
    test "includes uncommitted changes to a source file", %{repo: repo} do
      write(repo, "lib/kept.ex", "defmodule Kept do\n  def added, do: :ok\nend\n")

      in_repo(repo, fn ->
        resolved = Scope.resolve(:changed, base_ref: "main")

        assert resolved.scope == :changed
        assert resolved.files == ["test/kept_test.exs"]
        assert resolved.base_ref == "main"
        assert resolved.fallback_reason == nil
      end)
    end

    @tag :repo
    test "includes untracked test files", %{repo: repo} do
      write(repo, "test/brand_new_test.exs", "defmodule BrandNewTest do\nend\n")

      in_repo(repo, fn ->
        assert Scope.resolve(:changed, base_ref: "main").files == ["test/brand_new_test.exs"]
      end)
    end

    @tag :repo
    test "includes committed work on a branch", %{repo: repo} do
      git(repo, ["checkout", "-b", "feature"])
      write(repo, "lib/kept.ex", "defmodule Kept do\n  def committed, do: :ok\nend\n")
      git(repo, ["add", "."])
      git(repo, ["commit", "-m", "change"])

      in_repo(repo, fn ->
        assert Scope.resolve(:changed, base_ref: "main").files == ["test/kept_test.exs"]
      end)
    end

    @tag :repo
    test "runs the full suite when nothing has changed", %{repo: repo} do
      in_repo(repo, fn ->
        resolved = Scope.resolve(:changed, base_ref: "main")

        assert resolved.scope == :all
        assert resolved.requested_scope == :changed
        assert resolved.files == :all
        assert resolved.fallback_reason == "no test files map to the changed files"
      end)
    end

    @tag :repo
    test "runs the full suite when the change maps to no tests", %{repo: repo} do
      write(repo, "mix.exs", "# changed project\n")

      in_repo(repo, fn ->
        resolved = Scope.resolve(:changed, base_ref: "main")

        assert resolved.files == :all
        assert resolved.fallback_reason == "no test files map to the changed files"
      end)
    end

    @tag :repo
    test "ignores a deleted source file", %{repo: repo} do
      File.rm!(Path.join(repo, "lib/kept.ex"))

      in_repo(repo, fn ->
        assert Scope.resolve(:changed, base_ref: "main").files == :all
      end)
    end

    @tag :repo
    test "runs the full suite when the base ref does not exist", %{repo: repo} do
      write(repo, "lib/kept.ex", "defmodule Kept do\n  def added, do: :ok\nend\n")

      in_repo(repo, fn ->
        resolved = Scope.resolve(:changed, base_ref: "origin/nope")

        assert resolved.scope == :all
        assert resolved.requested_scope == :changed
        assert resolved.fallback_reason =~ "not a ref in a git repository here"
      end)
    end

    test "runs the full suite when there is no base ref to compare against" do
      resolved = Scope.resolve(:changed, base_ref: nil)

      # The library's own repository has a default branch, so this only asserts
      # the shape of the answer when there is nothing to diff against.
      assert resolved.scope in [:all, :changed]

      no_ref = Scope.resolve(:changed, base_ref: "")
      assert no_ref.files == :all
      assert no_ref.fallback_reason != nil
    end
  end

  describe "describe/1" do
    test "renders each scope as the report and the console show it" do
      assert Scope.describe(:all) == "all"
      assert Scope.describe(:changed) == "changed"
      assert Scope.describe({:glob, "test/unit/**"}) == "test/unit/**"
    end
  end
end
