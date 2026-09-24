defmodule ExQuality.Stages.DocLinks do
  @moduledoc """
  Checks the relative links in a package's published Markdown against the
  places they are published, where ExDoc mostly accepts a broken one silently.

  ExDoc rewrites a relative `.md` link to the matching `.html` page only when
  the target is itself one of the project's `extras`, and it looks the target
  up by basename alone. Every other relative link stays a raw `href`: it works
  on GitHub and answers 404 on HexDocs. ExDoc warns that a Markdown, `.txt` or
  extension-less target "does not exist" (even when it is on disk) and says
  nothing about any other target, such as `mix.exs` or a source file. A link
  whose basename happens to match some other extra is rewritten to *that*
  extra without a word, so a link to `docs/adr/README.md` lands on the
  package's front page. The hex.pm package page renders the README from the
  package tarball, so a relative path in the README resolves against the
  files the package ships and answers 404 there unless the file is among
  them.

      ✓ Doc links: 42 links checked (0.1s)
      ✗ Doc links: 3 problems (0.1s)

  Each problem is a finding at the `file:line` of the link:

      docs/holds.md
        12  [error] links to docs/adr/0001-holds.md, which is not in extras; HexDocs answers 404 for it (not_an_extra)

  ## Rules

  - `readme_not_packaged` - a relative link or image in `README.md` whose
    target is not covered by the package's files. When `package` names no
    `files:`, Hex's default list applies (`lib`, `priv`, `.formatter.exs`,
    `mix.exs`, `README*`, `readme*`, `LICENSE*`, `license*`, `CHANGELOG*`,
    `changelog*`, `src`, `c_src`, `Makefile*`), and the stage checks against
    that rather than reporting nothing.
  - `not_an_extra` - a relative link in a Markdown extra whose target is not
    itself an extra. A link into a directory the docs config copies with
    `assets:` is not one: ExDoc publishes those files as they are.
  - `duplicate_extra` - two extras that share a basename, with no `filename:`
    on the second. The finding is at the second one's line in `mix.exs`.
  - `rewritten_to_other_extra` - a relative link ExDoc would rewrite to a
    different extra than the file it names, because the basename matches that
    extra and ExDoc resolves a basename to the last extra declared with it.

  Absolute URLs, `mailto:` and ExDoc's own `e:`, `m:` and backticked forms,
  anchors and absolute paths are ignored; an anchor or query on a relative link
  is stripped before the check. Links inside code spans and fenced code blocks
  are not links. Images are checked only in the README, whose preview is the
  one place a missing image is not the docs config's business (`assets:`).

  Links in moduledocs and function docs are the Docs stage's
  (`ExQuality.Stages.Docs`): ExDoc warns on those.

  ## What it reads

  The project's own config, not the built output: `extras` from the `docs`
  config (a keyword list, or a zero-arity function returning one, as ExDoc
  accepts; each extra a path or a `{path, opts}` pair) and `files` from the
  `package` config. It builds nothing and runs no tool, so it takes well under
  a second.

  ## Opt-in

  Like the Docs stage this one is **off by default**, even when `:ex_doc` is
  installed: enabling it on detection would turn currently-green gates red on
  upgrade, and this project does not move anyone's gate by default. Enable it
  in `.quality.exs`:

      doc_links: [enabled: :auto]   # on when :ex_doc is installed (recommended)
      doc_links: [enabled: true]    # forced, with or without :ex_doc
  """

  alias ExQuality.Finding
  alias ExQuality.Umbrella

  # Hex's own default for `package: [files: ...]` (Hex 2.2, `Hex.Package`),
  # used when a project names no files, so a README link is still checked
  # against what the tarball will really carry.
  @hex_default_files ~w(lib priv .formatter.exs mix.exs README* readme* LICENSE* license* CHANGELOG* changelog* src c_src Makefile*)

  # Extras ExDoc renders as Markdown. `.txt` and extension-less extras are
  # rendered as preformatted text, so they carry no links.
  @markdown_extensions [".md", ".livemd", ".cheatmd"]

  # The extensions ExDoc resolves a relative link against extras for, by
  # basename (`ExDoc.Autolink`'s `@builtin_ext`).
  @rewritten_extensions [".md", ".livemd", ".cheatmd", ".txt", ""]

  @readme "README.md"

  @doc """
  Runs the doc links stage.

  ## Config options

  - `enabled` - `false` (default) | `:auto` (on when `:ex_doc` is installed) |
    `true` (forced)
  """
  @spec run(keyword()) :: ExQuality.Stage.result()
  def run(_config) do
    start_time = System.monotonic_time(:millisecond)
    project = Mix.Project.config()
    root = File.cwd!()

    extras = extras(project, root)
    scanned = scan(extras, root)
    readme = readme_references(root)

    findings =
      duplicate_findings(extras, root) ++
        readme_findings(readme, project, root) ++
        Enum.flat_map(scanned, &link_findings(&1, extras, project, root))

    link_count = link_count([{@readme, readme} | scanned])

    report(Finding.sort(findings), link_count, System.monotonic_time(:millisecond) - start_time)
  end

  defp report([], link_count, duration_ms) do
    %{
      name: "Doc links",
      status: :ok,
      output: "",
      stats: %{link_count: link_count, finding_count: 0},
      summary: "#{link_count} link#{plural(link_count)} checked",
      duration_ms: duration_ms
    }
  end

  defp report(findings, link_count, duration_ms) do
    count = length(findings)

    %{
      name: "Doc links",
      status: :error,
      output: Enum.map_join(findings, "\n", & &1.raw),
      findings: findings,
      stats: %{link_count: link_count, finding_count: count},
      summary: "#{count} problem#{plural(count)}",
      duration_ms: duration_ms
    }
  end

  ## Configuration

  # Each extra as `%{path: relative path, filename: the filename: option}`, in
  # declaration order. URL extras (`url:`) are links in the sidebar, not files.
  defp extras(project, root) do
    project
    |> docs_config()
    |> Keyword.get(:extras, [])
    |> Enum.flat_map(fn
      {path, opts} when is_list(opts) or is_map(opts) ->
        opts = Map.new(opts)

        if Map.has_key?(opts, :url),
          do: [],
          else: [%{path: normalize(to_string(path), root), filename: opts[:filename]}]

      path when is_binary(path) or is_atom(path) ->
        [%{path: normalize(to_string(path), root), filename: nil}]
    end)
  end

  defp docs_config(project) do
    case Keyword.get(project, :docs, []) do
      fun when is_function(fun, 0) -> fun.()
      docs when is_list(docs) -> docs
      _other -> []
    end
  end

  defp assets(project) do
    project
    |> docs_config()
    |> Keyword.get(:assets, %{})
    |> case do
      assets when is_map(assets) or is_list(assets) -> Enum.to_list(assets)
      _other -> []
    end
  end

  defp package_files(project) do
    case get_in(project, [:package, :files]) do
      nil -> @hex_default_files
      files -> files
    end
  end

  ## Rule (c): duplicate basenames

  defp duplicate_extra_line(path, root) do
    root
    |> Path.join("mix.exs")
    |> File.read()
    |> case do
      {:ok, source} ->
        source
        |> String.split("\n")
        |> Enum.with_index(1)
        |> Enum.filter(fn {line, _n} -> String.contains?(line, ~s("#{path}")) end)
        |> List.last()
        |> case do
          nil -> nil
          {_line, n} -> n
        end

      {:error, _reason} ->
        nil
    end
  end

  defp duplicate_findings(extras, root) do
    extras
    |> Enum.reduce({%{}, []}, fn extra, {seen, findings} ->
      base = Path.basename(extra.path)

      case Map.fetch(seen, base) do
        {:ok, first} when is_nil(extra.filename) ->
          finding =
            finding(
              "mix.exs",
              duplicate_extra_line(extra.path, root),
              "duplicate_extra",
              "extras #{first} and #{extra.path} share the basename #{base}; " <>
                "give #{extra.path} a filename: option"
            )

          {seen, [finding | findings]}

        {:ok, _first} ->
          {seen, findings}

        :error ->
          {Map.put(seen, base, extra.path), findings}
      end
    end)
    |> elem(1)
  end

  ## Rule (a): the README's links against the package files

  # The README's links, images included: the hex.pm preview resolves both.
  defp readme_references(root) do
    case File.read(Path.join(root, @readme)) do
      {:ok, text} -> references(text, :all)
      {:error, _reason} -> []
    end
  end

  defp readme_findings([], _project, _root), do: []

  defp readme_findings(refs, project, root) do
    covered =
      project
      |> package_files()
      |> Enum.flat_map(&Path.wildcard(Path.join(root, &1)))
      |> Enum.map(&Path.relative_to(&1, root))

    Enum.flat_map(refs, fn {line, target} ->
      resolved = resolve(@readme, target, root)

      if packaged?(resolved, covered) do
        []
      else
        [
          finding(
            @readme,
            line,
            "readme_not_packaged",
            "links to #{resolved}, which the package does not ship; " <>
              "the hex.pm README preview answers 404 for it"
          )
        ]
      end
    end)
  end

  # A README that is also an extra is read twice, once per rule; a link is
  # still one link.
  defp link_count(scanned) do
    scanned
    |> Enum.flat_map(fn {file, refs} ->
      Enum.map(refs, fn {line, target} -> {file, line, target} end)
    end)
    |> MapSet.new()
    |> MapSet.size()
  end

  defp packaged?(path, covered) do
    Enum.any?(covered, fn entry -> path == entry or String.starts_with?(path, entry <> "/") end)
  end

  ## Rules (b) and (d): links in the Markdown extras

  # `{file, [{line, target}]}` for every Markdown extra that is on disk.
  defp scan(extras, root) do
    Enum.flat_map(extras, fn %{path: path} ->
      with true <- Path.extname(path) in @markdown_extensions,
           {:ok, text} <- File.read(Path.join(root, path)) do
        [{path, references(text, :links)}]
      else
        _missing -> []
      end
    end)
  end

  defp link_findings({file, refs}, extras, project, root) do
    paths = MapSet.new(extras, & &1.path)
    # ExDoc keeps one extra per basename, the last one declared.
    by_basename = Map.new(extras, &{Path.basename(&1.path), &1.path})
    assets = assets(project)

    Enum.flat_map(refs, fn {line, target} ->
      resolved = resolve(file, target, root)
      rewritten_to = rewritten_to(target, by_basename)

      cond do
        rewritten_to != nil and rewritten_to != resolved ->
          [
            finding(
              file,
              line,
              "rewritten_to_other_extra",
              "links to #{resolved}, which ExDoc rewrites to the extra #{rewritten_to} " <>
                "because they share the basename #{Path.basename(resolved)}"
            )
          ]

        MapSet.member?(paths, resolved) or asset?(target, assets, root) ->
          []

        true ->
          [
            finding(
              file,
              line,
              "not_an_extra",
              "links to #{resolved}, which is not in extras; HexDocs answers 404 for it"
            )
          ]
      end
    end)
  end

  defp rewritten_to(target, by_basename) do
    if Path.extname(target) in @rewritten_extensions do
      Map.get(by_basename, Path.basename(target))
    end
  end

  # ExDoc copies each `assets:` source directory to its target directory, so a
  # link under the target that names a file in the source is published as is.
  defp asset?(target, assets, root) do
    Enum.any?(assets, fn {source, dest} ->
      prefix = String.trim_trailing(to_string(dest), "/") <> "/"

      String.starts_with?(target, prefix) and
        File.exists?(Path.join([root, to_string(source), String.trim_leading(target, prefix)]))
    end)
  end

  ## Link extraction

  # `[{line, relative target}]`, anchors and queries stripped. `:links` reads
  # Markdown links and reference definitions; `:all` adds Markdown images and
  # HTML `src`/`href` attributes, which the hex.pm README preview resolves too.
  defp references(text, kind) do
    text
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.reduce({[], false}, fn {line, n}, {acc, fenced?} ->
      cond do
        fence?(line) -> {acc, not fenced?}
        fenced? -> {acc, true}
        true -> {Enum.reverse(line_references(line, n, kind), acc), false}
      end
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  defp fence?(line), do: String.match?(line, ~r/^\s{0,3}(```|~~~)/)

  @code_span ~r/``[^`]*``|`[^`]*`/
  @inline_link ~r/(!?)\[(?:[^\[\]]|\[[^\[\]]*\])*\]\(\s*(<[^>]*>|[^\s()]+(?:\([^\s()]*\)[^\s()]*)*)(?:\s+(?:"[^"]*"|'[^']*'))?\s*\)/
  @reference_definition ~r/^\s{0,3}\[(?!\^)[^\]]+\]:\s*(<[^>]*>|\S+)/
  @html_attribute ~r/\s(?:src|href)\s*=\s*["']([^"']+)["']/

  defp line_references(line, n, kind) do
    line = Regex.replace(@code_span, line, "")

    inline =
      @inline_link
      |> Regex.scan(line)
      |> Enum.flat_map(fn
        [_match, "", target] -> [target]
        [_match, "!", target] -> if kind == :all, do: [target], else: []
      end)

    definitions = @reference_definition |> Regex.scan(line) |> Enum.map(&List.last/1)

    html =
      if kind == :all,
        do: @html_attribute |> Regex.scan(line) |> Enum.map(&List.last/1),
        else: []

    for target <- inline ++ definitions ++ html,
        path = relative_path(target),
        do: {n, path}
  end

  defp relative_path(target) do
    target = target |> String.trim_leading("<") |> String.trim_trailing(">")

    cond do
      target == "" -> nil
      String.starts_with?(target, ["#", "/", "`"]) -> nil
      String.match?(target, ~r/^[a-zA-Z][a-zA-Z0-9+.\-]*:/) -> nil
      true -> target |> String.split(["#", "?"], parts: 2) |> hd() |> URI.decode() |> nonempty()
    end
  end

  defp nonempty(""), do: nil
  defp nonempty(path), do: path

  ## Paths

  defp resolve(from_file, target, root) do
    from_file |> Path.dirname() |> Path.join(target) |> normalize(root)
  end

  defp normalize(path, root), do: path |> Path.expand(root) |> Path.relative_to(root)

  defp finding(file, line, check, message) do
    %Finding{
      file: file,
      line: line,
      app: Umbrella.app_for_path(file, Umbrella.apps_paths()),
      severity: :error,
      check: check,
      message: message,
      raw: "#{location(file, line)}: #{message}"
    }
  end

  defp location(file, nil), do: file
  defp location(file, line), do: "#{file}:#{line}"

  defp plural(1), do: ""
  defp plural(_count), do: "s"
end
