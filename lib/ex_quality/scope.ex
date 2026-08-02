defmodule ExQuality.Scope do
  @moduledoc """
  Resolves *how much code* a stage runs over, as opposed to *which stages* run.

  Every skip switch this library has narrows stages. An agent iterating on one
  file does not want fewer checks, it wants the same checks over less code: on a
  3,700-test umbrella the suite is 68% of a run's wall clock, and a one-file
  change needs a handful of test files rather than all of them.

  A scope is one of:

  - `:all` - everything, which is what an unscoped run has always done
  - `:changed` - the test files that map to the files changed against a base ref
  - a glob string - the test files matching it

  ## The one failure mode that matters

  A scoped run that resolves to no files must never report green, because it
  fails in the safe-looking direction: `mix quality` exits 0, the report says
  `"status": "ok"`, and nothing ran. So an empty resolution is not an empty run,
  it falls back to the full suite and says why in `fallback_reason`.

  For the same reason `resolve/2` reports the scope it *achieved*, not the one it
  was asked for. A run that fell back reports `scope: :all` with the request
  kept in `requested_scope`, so a caller that refuses to move a baseline on a
  scoped run does not have to reason about fallbacks.

  ## Uncommitted work counts

  An agent mid-task has everything uncommitted, so a diff that reads only
  committed history reports no changes on exactly the runs this exists for.
  `:changed` reads the working tree against the merge base with the base ref,
  and folds in untracked files.

  ## Example

      ExQuality.Scope.resolve(:changed, base_ref: "origin/main")
      #=> %{
      #=>   scope: :changed,
      #=>   requested_scope: :changed,
      #=>   files: ["test/user_test.exs"],
      #=>   base_ref: "origin/main",
      #=>   fallback_reason: nil
      #=> }
  """

  @typedoc "A requested scope."
  @type t :: :all | :changed | {:glob, String.t()}

  @typedoc """
  What a scope resolved to.

  `files` is `:all` for a full suite, which is not the same as `[]`: an empty
  list would be a run of nothing.
  """
  @type resolved :: %{
          scope: :all | :changed | {:glob, String.t()},
          requested_scope: t(),
          files: :all | [String.t()],
          base_ref: String.t() | nil,
          fallback_reason: String.t() | nil
        }

  # Ordered by how likely each is to be the trunk of a repository that has not
  # told us. `origin/HEAD` is asked first because it is the repository's own
  # answer rather than a guess.
  @base_ref_candidates ["origin/main", "origin/master", "main", "master"]

  @doc """
  Parses a scope written by a human, in `.quality.exs` or on the command line.

  Anything that is not `all` or `changed` is a glob, because a glob is the only
  one of the three that has to carry a value.

      iex> ExQuality.Scope.parse("changed")
      {:ok, :changed}

      iex> ExQuality.Scope.parse(:all)
      {:ok, :all}

      iex> ExQuality.Scope.parse("test/unit/**/*_test.exs")
      {:ok, {:glob, "test/unit/**/*_test.exs"}}

      iex> ExQuality.Scope.parse(42)
      {:error, "test scope must be :all, :changed or a glob string, got: 42"}
  """
  @spec parse(term()) :: {:ok, t()} | {:error, String.t()}
  def parse(:all), do: {:ok, :all}
  def parse("all"), do: {:ok, :all}
  def parse(:changed), do: {:ok, :changed}
  def parse("changed"), do: {:ok, :changed}
  # Idempotent, so an already-parsed scope can be put back into the config and
  # read out of it again.
  def parse({:glob, glob} = scope) when is_binary(glob) and glob != "", do: {:ok, scope}
  def parse(glob) when is_binary(glob) and glob != "", do: {:ok, {:glob, glob}}

  def parse(other) do
    {:error, "test scope must be :all, :changed or a glob string, got: #{inspect(other)}"}
  end

  @doc """
  Returns the scope a loaded config asks the test stage for.

  Raises when the config names something that is not a scope, rather than
  falling back to `:all`: a typo that silently ran everything would be slow, and
  one that silently ran nothing would be a green run of no tests.

      iex> ExQuality.Scope.from_config([])
      :all

      iex> ExQuality.Scope.from_config(test: [scope: :changed])
      :changed
  """
  @spec from_config(keyword()) :: t()
  def from_config(config) do
    value = config |> Keyword.get(:test, []) |> Keyword.get(:scope, :all)

    case parse(value) do
      {:ok, scope} -> scope
      {:error, message} -> Mix.raise(message)
    end
  end

  @doc """
  Renders a scope for the report and for human output.

      iex> ExQuality.Scope.describe(:all)
      "all"

      iex> ExQuality.Scope.describe({:glob, "test/unit/**"})
      "test/unit/**"
  """
  @spec describe(t()) :: String.t()
  def describe(:all), do: "all"
  def describe(:changed), do: "changed"
  def describe({:glob, glob}), do: glob

  @doc """
  Resolves a scope to the test files to run.

  ## Options

  - `:base_ref` - what `:changed` is measured against (default: the repository's
    default branch, see `default_base_ref/0`)
  """
  @spec resolve(t(), keyword()) :: resolved()
  def resolve(scope, opts \\ [])

  def resolve(:all, _opts), do: full(:all, nil, nil)

  def resolve(:changed, opts) do
    base_ref = Keyword.get(opts, :base_ref) || default_base_ref()

    case changed_files(base_ref) do
      {:ok, changed} ->
        scoped(:changed, test_files(changed), base_ref, "no test files map to the changed files")

      {:error, reason} ->
        full(:changed, base_ref, reason)
    end
  end

  def resolve({:glob, glob} = scope, _opts) do
    matches = glob |> Path.wildcard() |> Enum.filter(&test_file?/1) |> Enum.sort()

    scoped(scope, matches, nil, "the glob matched no test files")
  end

  # An empty resolution runs everything. See the moduledoc: a scoped green over
  # nothing is the one outcome that would make this worse than not having it.
  defp scoped(scope, [], base_ref, reason), do: full(scope, base_ref, reason)

  defp scoped(scope, files, base_ref, _reason) do
    %{
      scope: scope,
      requested_scope: scope,
      files: files,
      base_ref: base_ref,
      fallback_reason: nil
    }
  end

  defp full(requested, base_ref, reason) do
    %{
      scope: :all,
      requested_scope: requested,
      files: :all,
      base_ref: base_ref,
      fallback_reason: reason
    }
  end

  @doc """
  Returns the ref `:changed` is measured against when nothing names one.

  The repository's own `origin/HEAD` is preferred, because a repository whose
  trunk is neither `main` nor `master` has still recorded which one it is.
  Returns `nil` outside a git repository, which `resolve/2` turns into a full
  suite rather than a failure.
  """
  @spec default_base_ref() :: String.t() | nil
  def default_base_ref do
    case git(["symbolic-ref", "--short", "refs/remotes/origin/HEAD"]) do
      {:ok, ref} -> ref
      {:error, _reason} -> Enum.find(@base_ref_candidates, &ref_exists?/1)
    end
  end

  defp ref_exists?(ref) do
    match?({:ok, _sha}, git(["rev-parse", "--verify", "--quiet", ref <> "^{commit}"]))
  end

  # Everything changed since the branch point, plus everything not yet
  # committed. The merge base rather than the ref itself, so commits landed on
  # the trunk since the branch started do not read as this branch's work.
  defp changed_files(nil), do: {:error, "no base ref could be determined"}

  defp changed_files(base_ref) do
    with {:ok, root} <- git(["rev-parse", "--show-toplevel"]),
         {:ok, base} <- merge_base(base_ref) do
      {:ok, tracked_changes(base) ++ untracked_files()} |> relative_to(root)
    else
      {:error, _reason} -> {:error, "#{inspect(base_ref)} is not a ref in a git repository here"}
    end
  end

  defp merge_base(base_ref) do
    case git(["merge-base", "HEAD", base_ref]) do
      {:ok, sha} -> {:ok, sha}
      # An unrelated history, or a shallow clone with no common commit. The ref
      # itself is still a usable comparison point.
      {:error, _reason} -> if ref_exists?(base_ref), do: {:ok, base_ref}, else: {:error, :no_base}
    end
  end

  # `-d` drops deletions: a deleted source file has no test to run, and a
  # deleted test file cannot be pointed at.
  defp tracked_changes(base) do
    case git(["diff", "--name-only", "--diff-filter=d", base]) do
      {:ok, output} -> lines(output)
      {:error, _reason} -> []
    end
  end

  defp untracked_files do
    case git(["ls-files", "--others", "--exclude-standard"]) do
      {:ok, output} -> lines(output)
      {:error, _reason} -> []
    end
  end

  # git reports paths from the repository root, and a run may be started from a
  # directory below it, so they are put back into the caller's terms.
  defp relative_to({:ok, paths}, root) do
    {:ok, Enum.map(paths, &(root |> Path.join(&1) |> Path.relative_to_cwd()))}
  end

  defp lines(output) do
    output |> String.split("\n", trim: true) |> Enum.map(&String.trim/1)
  end

  @doc """
  Maps changed files to the test files that cover them.

  A changed test file is itself. A changed source file is the test file beside
  it, `lib/foo/bar.ex` to `test/foo/bar_test.exs`, which works unchanged in an
  umbrella because `apps/web/lib/foo.ex` maps under `apps/web/test/`.

  Only files that exist are returned. Everything else - a changed `mix.exs`, a
  source file with no test - contributes nothing, and contributing nothing is
  what makes `resolve/2` fall back to the full suite.

      iex> ExQuality.Scope.test_files(["mix.exs"])
      []
  """
  @spec test_files([String.t()]) :: [String.t()]
  def test_files(changed) do
    changed
    |> Enum.flat_map(fn path ->
      cond do
        test_file?(path) -> [path]
        mapped = mapped_test_file(path) -> [mapped]
        true -> []
      end
    end)
    |> Enum.filter(&File.regular?/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp test_file?(path), do: String.ends_with?(path, "_test.exs")

  defp mapped_test_file(path) do
    segments = Path.split(path)

    with true <- String.ends_with?(path, ".ex"),
         index when is_integer(index) <- Enum.find_index(segments, &(&1 == "lib")) do
      segments
      |> List.replace_at(index, "test")
      |> Path.join()
      |> String.replace_suffix(".ex", "_test.exs")
    else
      _no_mapping -> nil
    end
  end

  # git is asked about the repository, never told to change it, so a failure here
  # is always "this question has no answer" rather than something to report.
  defp git(args) do
    case System.cmd("git", args, stderr_to_stdout: true) do
      {output, 0} -> {:ok, String.trim(output)}
      {output, code} -> {:error, "git #{hd(args)} exited #{code}: #{String.trim(output)}"}
    end
  rescue
    # No git on PATH at all.
    ErlangError -> {:error, "git is not available"}
  end
end
