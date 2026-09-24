defmodule ExQuality.Stages.Docs do
  @moduledoc """
  Builds the documentation with `mix docs` and fails on any ExDoc warning.

  ExDoc warns about real defects a reader will hit - a reference to a function
  that does not exist, a moduledoc link that resolves nowhere, an undefined
  anchor - and a plain `mix docs` exits 0 anyway. Warnings that fail no build
  accumulate, so this stage is the ratchet: a project that reaches zero
  warnings stays there.

      ✓ Docs: No warnings (2.1s)
      ✗ Docs: 3 warnings (1.9s)

  Each warning becomes a finding at the `file:line` ExDoc reports:

      lib/my_app/user.ex
        42  [error] documentation references function MyApp.User.fetch/2 but it is undefined or private (ex_doc)

  Both shapes ExDoc prints a warning in are read: the Elixir 1.18 diagnostic,
  an indented `warning:` line whose location closes the block on a
  `└─ file:line:` line, and the older form, a `warning:` line at the start of
  the line followed by an indented `file:line:` line. A warning ExDoc reports
  without a location falls back to the tool's output verbatim, so a warning is
  never hidden behind a parse.

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

  `mix docs --formatter html --output <tmp dir> --warnings-as-errors`: one
  formatter, because the epub build repeats the html build's warnings, and a
  temporary output directory that is deleted after the run, because a checker
  that leaves a `doc/` tree behind has written to the repository. The
  project's own `mix docs` output is untouched.

  `--warnings-as-errors` makes ExDoc 0.36 and later exit non-zero when it
  warned, which backs the parse: a warning printed in a shape the stage does
  not read still fails the stage, as `ExDoc reported warnings (see output)`,
  instead of passing as `No warnings`. Earlier ExDoc versions accept the flag
  and ignore it, so there the parse alone decides.
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
      System.cmd("mix", ["docs", "--formatter", "html", "--output", out, "--warnings-as-errors"],
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
          summary: failure_summary(output),
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

  # ExDoc exits non-zero under --warnings-as-errors when it warned; if the
  # parse found none of those warnings, say that rather than "failed".
  defp failure_summary(output) do
    if String.contains?(output, "--warnings-as-errors"),
      do: "ExDoc reported warnings (see output)",
      else: "mix docs failed (see output)"
  end

  # An ExDoc warning is a `warning:` line followed by indented context lines,
  # usually carrying a `file:line:` location. Elixir 1.18 prints it as an
  # indented diagnostic that closes on a `└─` location line:
  #
  #          warning: documentation references function "Foo.bar/1" but it is undefined or private
  #          │
  #      118 │ See `Foo.bar/1`.
  #          │ ~~~~~~~~~~~~~~~~
  #          │
  #          └─ README.md:118: (file)
  #
  # and earlier versions print it unindented, the location on its own line:
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
      String.match?(line, ~r/^\s*warning:/) ->
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
            message: first |> String.trim_leading() |> String.replace_prefix("warning: ", ""),
            raw: Enum.join(block, "\n")
          }
        ]
    end
  end

  # A block with a `└─` line is a diagnostic: that line alone is its location,
  # so an excerpt line can never be read as one. Without it, the older form's
  # first indented `file:line` is.
  defp location(block) do
    case Enum.filter(block, &String.match?(&1, ~r/^\s*└─/u)) do
      [] -> Enum.find_value(block, &location_in(&1, ~r/^\s+(\S+?):(\d+)/))
      closing -> Enum.find_value(closing, &location_in(&1, ~r/^\s*└─\s*(\S+?):(\d+)/u))
    end
  end

  defp location_in(line, regex) do
    case Regex.run(regex, line) do
      [_, file, line_number] -> {Finding.relative_path(file), String.to_integer(line_number)}
      nil -> nil
    end
  end

  defp plural(1), do: ""
  defp plural(_count), do: "s"
end
