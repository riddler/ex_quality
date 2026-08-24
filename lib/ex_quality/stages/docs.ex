defmodule ExQuality.Stages.Docs do
  @moduledoc """
  Builds the documentation with `mix docs` and fails on any ExDoc warning.

  ExDoc warns about real defects a reader will hit - a reference to a function
  that does not exist, a moduledoc link that resolves nowhere, an undefined
  anchor - and `mix docs` exits 0 anyway on most versions. Warnings that fail
  no build accumulate, so this stage is the ratchet: a project that reaches
  zero warnings stays there.

      ✓ Docs: No warnings (2.1s)
      ✗ Docs: 3 warnings (1.9s)

  Each warning becomes a finding at the `file:line` ExDoc reports:

      lib/my_app/user.ex
        42  [error] documentation references function MyApp.User.fetch/2 but it is undefined or private (ex_doc)

  A warning ExDoc reports without a location falls back to the tool's output
  verbatim, so a warning is never hidden behind a parse.

  ## Opt-in

  Unlike the other tool-backed stages this one is **off by default**, even when
  `:ex_doc` is installed. Nearly every published package depends on `:ex_doc`
  to build its docs, so enabling on detection would turn currently-green gates
  red on upgrade, and this project does not move anyone's gate by default.
  Enable it in `.quality.exs`:

      docs: [enabled: :auto]   # on when :ex_doc is installed (recommended)
      docs: [enabled: true]    # forced; errors if :ex_doc is missing

  With `enabled: :auto` a project without `:ex_doc` reports the stage as
  skipped (`:ex_doc not installed`), the way doctor and sobelow do.

  ## What it builds

  `mix docs --formatter html --output <tmp dir>`: one formatter, because the
  epub build repeats the html build's warnings, and a temporary output
  directory that is deleted after the run, because a checker that leaves a
  `doc/` tree behind has written to the repository. The project's own
  `mix docs` output is untouched.
  """

  alias ExQuality.Aliases
  alias ExQuality.Finding
  alias ExQuality.Umbrella

  @doc """
  Runs the docs stage.

  ## Config options

  - `enabled` - `false` (default) | `:auto` (on when `:ex_doc` is installed) |
    `true` (forced)
  """
  @spec run(keyword()) :: ExQuality.Stage.result()
  def run(_config) do
    if Aliases.shadowing?("docs") do
      Aliases.shadowed("Docs", "docs")
    else
      build_docs()
    end
  end

  defp build_docs do
    start_time = System.monotonic_time(:millisecond)
    out = out_path()

    {output, exit_code} =
      System.cmd("mix", ["docs", "--formatter", "html", "--output", out],
        env: [{"MIX_ENV", "dev"}],
        stderr_to_stdout: true
      )

    _removed = File.rm_rf(out)

    report(output, exit_code, System.monotonic_time(:millisecond) - start_time)
  end

  defp out_path do
    Path.join(System.tmp_dir!(), "ex_quality-docs-#{:erlang.unique_integer([:positive])}")
  end

  defp report(output, exit_code, duration_ms) do
    warnings = parse_warnings(output)

    cond do
      warnings != [] ->
        %{
          name: "Docs",
          status: :error,
          output: output,
          findings: findings(warnings),
          stats: %{warning_count: length(warnings)},
          summary: "#{length(warnings)} warning#{plural(length(warnings))}",
          duration_ms: duration_ms
        }

      exit_code != 0 ->
        %{
          name: "Docs",
          status: :error,
          output: output,
          stats: %{},
          summary: "mix docs failed (see output)",
          duration_ms: duration_ms
        }

      true ->
        %{
          name: "Docs",
          status: :ok,
          output: output,
          stats: %{warning_count: 0},
          summary: "No warnings",
          duration_ms: duration_ms
        }
    end
  end

  # An ExDoc warning is a `warning:` line followed by indented context lines,
  # usually ending in a `file:line:` location:
  #
  #     warning: documentation references function Foo.bar/1 but it is
  #     undefined or private
  #       lib/foo.ex:10: Foo.baz/0
  #
  defp parse_warnings(output) do
    output
    |> String.split("\n")
    |> Enum.chunk_while([], &chunk_line/2, &chunk_rest/1)
  end

  defp chunk_line(line, block) do
    cond do
      String.starts_with?(line, "warning:") ->
        if block == [], do: {:cont, [line]}, else: {:cont, Enum.reverse(block), [line]}

      block != [] and String.match?(line, ~r/^\s+\S/) ->
        {:cont, [line | block]}

      block != [] ->
        {:cont, Enum.reverse(block), []}

      true ->
        {:cont, []}
    end
  end

  defp chunk_rest([]), do: {:cont, []}
  defp chunk_rest(block), do: {:cont, Enum.reverse(block), []}

  # Findings are worth rendering only when every warning produced one: a
  # warning ExDoc reported without a location must not vanish behind the
  # warnings that parsed, so the whole set falls back to output verbatim.
  defp findings(warnings) do
    apps = Umbrella.apps_paths()
    findings = Enum.flat_map(warnings, &finding(&1, apps))

    if length(findings) == length(warnings), do: Finding.sort(findings), else: []
  end

  defp finding([first | _rest] = block, apps) do
    case location(block) do
      nil ->
        []

      {file, line} ->
        [
          %Finding{
            file: file,
            line: line,
            app: Umbrella.app_for_path(file, apps),
            severity: :error,
            check: "ex_doc",
            message: String.replace_prefix(first, "warning: ", ""),
            raw: Enum.join(block, "\n")
          }
        ]
    end
  end

  defp location(block) do
    Enum.find_value(block, fn line ->
      case Regex.run(~r/^\s+(\S+?):(\d+)/, line) do
        [_, file, line_number] -> {Finding.relative_path(file), String.to_integer(line_number)}
        nil -> nil
      end
    end)
  end

  defp plural(1), do: ""
  defp plural(_count), do: "s"
end
