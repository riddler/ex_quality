defmodule ExQuality.Finding do
  @moduledoc """
  A single actionable problem reported by a stage.

  Stages parse their tool's output into findings so that ExQuality can render
  the minimum a reader needs in order to act: a `file:line`, a message, and the
  rule that produced it.

  A finding always carries the `raw` text it was derived from. If a parser is
  wrong about a tool's format, the finding degrades into "shows the original
  lines" rather than silently dropping a real problem.

  Stages that cannot parse their output leave `findings` empty, and the caller
  falls back to printing the tool's full output verbatim. Unparseable output is
  never hidden.

  ## Fields

  - `file` - path relative to the project root
  - `line` - 1-based line number, or `nil` when the tool did not report one
  - `column` - 1-based column, when the tool reports one
  - `app` - umbrella app the file belongs to, when known
  - `severity` - `:error`, `:warning` or `:info`
  - `check` - the tool's rule identifier (a check module, a category, a code)
  - `message` - the human-readable problem description
  - `raw` - the tool output lines this finding was derived from
  """

  @type severity :: :error | :warning | :info

  @type t :: %__MODULE__{
          file: String.t(),
          line: pos_integer() | nil,
          column: pos_integer() | nil,
          app: atom() | nil,
          severity: severity(),
          check: String.t() | nil,
          message: String.t(),
          raw: String.t()
        }

  @enforce_keys [:file, :message]
  defstruct [
    :file,
    :line,
    :column,
    :app,
    :check,
    :message,
    severity: :warning,
    raw: ""
  ]

  @doc """
  Normalises a path reported by a tool into one relative to the run's root.

  That root is the working directory, which is where `mix quality` is invoked
  from, and which is the project root - the umbrella root, in an umbrella. It
  is the same base `ExQuality.Umbrella.app_for_path/2` matches against, so a
  finding's `file` and its `app` cannot disagree about where it is.

  Tools disagree about this. Credo reports a relative path, mix_audit reports
  an absolute one, and a finding rendered as
  `/Users/someone/code/app/mix.lock` is worse than one rendered as `mix.lock`
  in every place a finding is used: it is longer to read, it does not match
  what the reader would type, it differs between a laptop and CI for the same
  problem, and it makes two reports of the same finding compare as different.

  A path outside the project root is left absolute, because shortening it would
  be a lie about where the file is. Anything that is not a path - a module name
  a coverage finding falls back to - passes through unchanged.

      iex> ExQuality.Finding.relative_path("mix.lock")
      "mix.lock"

      iex> ExQuality.Finding.relative_path(Path.join(File.cwd!(), "lib/user.ex"))
      "lib/user.ex"

      iex> ExQuality.Finding.relative_path(nil)
      nil
  """
  @spec relative_path(String.t() | nil) :: String.t() | nil
  def relative_path(nil), do: nil
  def relative_path(path) when is_binary(path), do: Path.relative_to_cwd(path)

  @doc """
  Builds a finding from a decoded JSON object, or returns `:error`.

  This is the reading half of the encoding in `ExQuality.Report`: it is what a
  custom stage's command uses to report structured findings, and what a
  consumer of a report uses to read one back.

  Only `file` and `message` are required, matching the struct's enforced keys.
  Everything else is optional and takes the struct's default when it is absent
  or the wrong shape, because a tool that got one field wrong should still have
  its finding read rather than dropped.

  `app` is inferred from the path against `apps` when the object does not name
  one, which is what the built-in stages do anyway and is one less thing for a
  custom tool to get wrong. Pass `ExQuality.Umbrella.apps_paths/0` as `apps`,
  read once rather than once per finding.

      iex> alias ExQuality.Finding
      iex> {:ok, finding} = Finding.from_map(%{"file" => "lib/a.ex", "message" => "no"})
      iex> {finding.file, finding.message, finding.severity}
      {"lib/a.ex", "no", :warning}

      iex> ExQuality.Finding.from_map(%{"message" => "nowhere to look"})
      :error
  """
  @spec from_map(map(), %{atom() => String.t()}) :: {:ok, t()} | :error
  def from_map(map, apps \\ %{})

  def from_map(%{"file" => file, "message" => message} = map, apps)
      when is_binary(file) and is_binary(message) do
    path = relative_path(file)

    {:ok,
     %__MODULE__{
       file: path,
       line: coordinate(map["line"]),
       column: coordinate(map["column"]),
       app: app(map["app"]) || ExQuality.Umbrella.app_for_path(path, apps),
       severity: severity(map["severity"]),
       check: text(map["check"]),
       message: message,
       raw: text(map["raw"]) || Jason.encode!(map)
     }}
  end

  def from_map(_other, _apps), do: :error

  defp coordinate(value) when is_integer(value) and value > 0, do: value
  defp coordinate(_other), do: nil

  defp text(value) when is_binary(value) and value != "", do: value
  defp text(_other), do: nil

  # A tool naming an app ex_quality has never heard of is a tool that is wrong
  # about the tree, not a reason to grow the atom table, so only apps that
  # already exist as atoms are taken.
  defp app(value) when is_binary(value) do
    String.to_existing_atom(value)
  rescue
    ArgumentError -> nil
  end

  defp app(_other), do: nil

  defp severity("error"), do: :error
  defp severity("warning"), do: :warning
  defp severity("info"), do: :info
  # Anything else takes the struct's default rather than being invented, so an
  # unknown level is still rendered rather than dropped.
  defp severity(_other), do: :warning

  @doc """
  Sorts findings by file, then line, then column.

  Findings without a line or column sort before those that have one, so a
  file-level finding leads the file's list.

      iex> alias ExQuality.Finding
      iex> findings = [
      ...>   %Finding{file: "b.ex", line: 1, message: "second"},
      ...>   %Finding{file: "a.ex", line: 9, message: "first"}
      ...> ]
      iex> Enum.map(Finding.sort(findings), & &1.message)
      ["first", "second"]
  """
  @spec sort([t()]) :: [t()]
  def sort(findings) do
    Enum.sort_by(findings, &{&1.file, &1.line || 0, &1.column || 0})
  end

  @doc """
  Groups findings by file, sorted by file name and by position within a file.

  Returns a list of `{file, findings}` tuples rather than a map, so the order
  is stable for rendering.

      iex> alias ExQuality.Finding
      iex> findings = [
      ...>   %Finding{file: "a.ex", line: 9, message: "later"},
      ...>   %Finding{file: "a.ex", line: 2, message: "earlier"}
      ...> ]
      iex> [{"a.ex", [first, second]}] = Finding.group_by_file(findings)
      iex> {first.message, second.message}
      {"earlier", "later"}
  """
  @spec group_by_file([t()]) :: [{String.t(), [t()]}]
  def group_by_file(findings) do
    findings
    |> sort()
    |> Enum.chunk_by(& &1.file)
    |> Enum.map(fn [%__MODULE__{file: file} | _rest] = group -> {file, group} end)
  end

  @doc """
  Groups findings by umbrella app, sorted by app name.

  Findings with no app come first, as one group under `nil`, so a single-app
  project produces exactly one group.

      iex> alias ExQuality.Finding
      iex> findings = [
      ...>   %Finding{file: "apps/b/lib/b.ex", app: :b, message: "b"},
      ...>   %Finding{file: "apps/a/lib/a.ex", app: :a, message: "a"}
      ...> ]
      iex> Enum.map(Finding.group_by_app(findings), &elem(&1, 0))
      [:a, :b]
  """
  @spec group_by_app([t()]) :: [{atom() | nil, [t()]}]
  def group_by_app(findings) do
    findings
    |> Enum.sort_by(&{&1.app != nil, &1.app, &1.file, &1.line || 0, &1.column || 0})
    |> Enum.chunk_by(& &1.app)
    |> Enum.map(fn [%__MODULE__{app: app} | _rest] = group -> {app, group} end)
  end

  @doc """
  Renders findings as a human-readable string, grouped by file.

  Findings that name an umbrella app are grouped by app first, under a header,
  because "which app is broken" is the first question a reader of a ten-app
  umbrella has.

  Returns an empty string for an empty list, so callers can test the result
  and fall back to raw tool output.

      iex> alias ExQuality.Finding
      iex> finding = %Finding{
      ...>   file: "lib/user.ex", line: 42, column: 3,
      ...>   severity: :warning, check: "readability",
      ...>   message: "Modules should have a @moduledoc tag."
      ...> }
      iex> Finding.render([finding])
      "lib/user.ex\\n  42:3  [warning] Modules should have a @moduledoc tag. (readability)\\n"
  """
  @spec render([t()]) :: String.t()
  def render([]), do: ""

  def render(findings) do
    if Enum.any?(findings, &(&1.app != nil)) do
      findings
      |> group_by_app()
      |> Enum.map_join("\n", &render_app_group/1)
    else
      render_files(findings)
    end
  end

  defp render_app_group({nil, findings}), do: render_files(findings)

  defp render_app_group({app, findings}), do: "── #{app} ──\n#{render_files(findings)}"

  defp render_files(findings) do
    findings
    |> group_by_file()
    |> Enum.map_join("\n", &render_file_group/1)
  end

  defp render_file_group({file, findings}) do
    positions = Enum.map(findings, &position/1)
    width = positions |> Enum.map(&String.length/1) |> Enum.max()

    lines =
      findings
      |> Enum.zip(positions)
      |> Enum.map_join("", fn {finding, position} ->
        "  #{String.pad_trailing(position, width)}  #{describe(finding)}\n"
      end)

    "#{file}\n#{lines}"
  end

  defp position(%__MODULE__{line: nil}), do: "-"
  defp position(%__MODULE__{line: line, column: nil}), do: "#{line}"
  defp position(%__MODULE__{line: line, column: column}), do: "#{line}:#{column}"

  defp describe(%__MODULE__{severity: severity, message: message, check: nil}) do
    "[#{severity}] #{message}"
  end

  defp describe(%__MODULE__{severity: severity, message: message, check: check}) do
    "[#{severity}] #{message} (#{check})"
  end
end
