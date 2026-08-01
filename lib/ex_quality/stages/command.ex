defmodule ExQuality.Stages.Command do
  @moduledoc """
  Runs a project's own check as a stage, described declaratively in
  `.quality.exs`.

  This is the ergonomic half of custom stages: a house rule, a schema linter, a
  mix task or a shell script gate becomes a stage of a `mix quality` run
  without anyone writing a module. The other half is a module implementing the
  `ExQuality.Stage` contract, for anything the command form cannot express.

      custom: [
        [
          key: :nullability,
          name: "Nullability",
          command: "mix",
          args: ["schema.nullability", "--format", "json"],
          env: [{"MIX_ENV", "test"}],
          kind: :reader
        ]
      ]

  Exit code 0 is `:ok`, anything else is `:error`. The command is run with
  `stderr_to_stdout: true`, as every other shelling stage is, so a tool that
  writes its complaint to stderr is not thrown away.

  ## Naming the command

  A bare name is looked up on the PATH. A command containing `/` is a path, and
  is expanded before it runs, so a project's own script can be named directly:

      command: "bin/checks/schema.sh"

  The path is relative to `cd:` when one is given and to the project root
  otherwise, so an entry reads as the shell it looks like: `cd <cd> &&
  <command> <args>`. An absolute path is used as it stands.

  ## The finding contract

  A command that wants structured findings prints one JSON document on stdout:

      {
        "summary": "2 unsound claims",
        "stats": {"finding_count": 2},
        "findings": [
          {
            "file": "lib/contacts/contact.ex",
            "line": 14,
            "column": null,
            "app": "web",
            "severity": "error",
            "check": "unsound",
            "message": "field :email is typed non-nil but the column is nullable"
          }
        ]
      }

  Only `file` and `message` are required per finding. `app` may be omitted and
  is inferred from the path. See `ExQuality.Finding.from_map/2`.

  Anything that does not parse falls through to `output` verbatim, which is the
  rule the printer and the report already follow. `parse: :none` skips the
  attempt for a command known to print prose, so a tool that happens to emit
  JSON for some other reason is not misread.

  ## Not applicable

  A custom check often has a prerequisite ExQuality cannot know about: a
  migrated test database, a running service, a generated file. Without a way to
  say "not applicable" the stage fails with an error that reads like a code
  problem. `skip_exit_code: 2` lets the command exit 2 and have the stage
  report `:skipped` with its own reason, which keeps the invariant that a stage
  saying nothing would read as a stage that passed.

  The reason is the document's `summary` when the command wrote one, and the
  first line of output otherwise. Prefer the document: a first line is hostage
  to whatever the toolchain prints ahead of the command's own output, and `mix`
  in particular emits `==> app` headers for an umbrella and a build-lock notice
  when another stage holds the lock.

  ## Reader versus writer

  `kind: :reader` is the default, and it is what most custom checks are: they
  read source, or query a database. A command that compiles, generates, or
  writes anything under `_build` or the repository must declare
  `kind: :writer`, because the analysis phase runs its readers concurrently and
  a stage that rewrites the beams underneath them makes another stage report a
  failure about the build rather than about the code.

  `MIX_ENV=test mix <task>` is normally still a reader here, because the
  Compile stage has already built dev and test before the analysis phase
  starts. That is the most common shape a custom command takes and it looks
  like a writer, so it is worth saying.
  """

  alias ExQuality.Finding
  alias ExQuality.Json
  alias ExQuality.Umbrella

  @doc """
  Runs one custom command entry and returns its stage result.

  The entry is the keyword list from `.quality.exs`, already validated by
  `ExQuality.Custom.validate!/1`.
  """
  @spec run(keyword()) :: ExQuality.Stage.result()
  def run(entry) do
    name = Keyword.fetch!(entry, :name)
    command = resolve(Keyword.fetch!(entry, :command), Keyword.get(entry, :cd))
    start_time = System.monotonic_time(:millisecond)

    outcome = execute(command, Keyword.get(entry, :args, []), cmd_opts(entry))

    duration_ms = System.monotonic_time(:millisecond) - start_time

    case outcome do
      {:ok, output, exit_code} -> result(entry, name, output, exit_code, duration_ms)
      {:error, reason} -> unrunnable(name, command, reason, duration_ms)
    end
  end

  # `System.cmd/3` resolves a bare name on the PATH and otherwise wants an
  # absolute path: even `./bin/check.sh` raises `:enoent`, because nothing
  # expands it. A repo's own script is the ordinary case for a custom stage, so
  # a command carrying a path separator is expanded here rather than left to
  # be written as `command: "bash", args: ["bin/check.sh"]`.
  #
  # Relative to `cd:` when one is given, so an entry reads as the shell it
  # looks like: `cd <cd> && <command> <args>`. An absolute command is returned
  # unchanged, and a bare name still goes to the PATH.
  defp resolve(command, cd) do
    if String.contains?(command, "/") do
      Path.expand(command, cd || File.cwd!())
    else
      command
    end
  end

  defp cmd_opts(entry) do
    opts = [env: Keyword.get(entry, :env, []), stderr_to_stdout: true]

    case Keyword.get(entry, :cd) do
      nil -> opts
      cd -> Keyword.put(opts, :cd, cd)
    end
  end

  # A command that is not on the PATH, or a `cd` that does not exist, raises
  # rather than returning an exit code. That is still a stage failure and not a
  # crash of the run, because every other stage reports its own trouble.
  defp execute(command, args, opts) do
    {output, exit_code} = System.cmd(command, args, opts)
    {:ok, output, exit_code}
  rescue
    error -> {:error, Exception.message(error)}
  end

  defp unrunnable(name, command, reason, duration_ms) do
    %{
      name: name,
      status: :error,
      output: "#{command} could not be run: #{reason}\n",
      stats: %{},
      summary: "Command could not be run",
      duration_ms: duration_ms
    }
  end

  defp result(entry, name, output, exit_code, duration_ms) do
    if exit_code == Keyword.get(entry, :skip_exit_code, :never) do
      %{
        name: name,
        status: :skipped,
        output: output,
        stats: %{},
        summary: skip_reason(entry, output),
        duration_ms: duration_ms
      }
    else
      report(entry, name, output, exit_code, duration_ms)
    end
  end

  # A skipped stage's reason is the one line a person reads, so it is taken
  # from the document's `summary` when the command wrote one. The first line of
  # output is the fallback, and on its own it is hostage to whatever the
  # toolchain prints first: `mix` emits `==> app` headers for an umbrella and a
  # build-lock notice when another stage holds the lock, either of which turns
  # a useful reason into noise.
  defp skip_reason(entry, output) do
    with %{"summary" => summary} <- document(entry, output),
         true <- is_binary(summary),
         trimmed when trimmed != "" <- String.trim(summary) do
      trimmed
    else
      _no_summary -> first_line(output)
    end
  end

  defp first_line(output) do
    output
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.find("not applicable", &(&1 != ""))
  end

  defp report(entry, name, output, exit_code, duration_ms) do
    status = if exit_code == 0, do: :ok, else: :error

    case document(entry, output) do
      nil ->
        %{
          name: name,
          status: status,
          output: output,
          stats: %{},
          summary: fallback_summary(status),
          duration_ms: duration_ms
        }

      document ->
        parsed(document, name, status, output, duration_ms)
    end
  end

  defp document(entry, output) do
    if Keyword.get(entry, :parse, :json) == :none do
      nil
    else
      case Json.decode(output) do
        {:ok, %{} = document} -> document
        _no_document -> nil
      end
    end
  end

  defp parsed(document, name, status, output, duration_ms) do
    findings = findings(document)

    %{
      name: name,
      status: status,
      output: output,
      findings: findings,
      stats: stats(document, findings),
      summary: summary(document, findings, status),
      duration_ms: duration_ms
    }
  end

  defp findings(%{"findings" => findings}) when is_list(findings) do
    apps = Umbrella.apps_paths()

    findings
    |> Enum.flat_map(fn
      %{} = finding ->
        case Finding.from_map(finding, apps) do
          {:ok, parsed} -> [parsed]
          :error -> []
        end

      _other ->
        []
    end)
    |> Finding.sort()
  end

  defp findings(_document), do: []

  # A custom stage's stats are its tool's own, so they are carried string-keyed
  # rather than atomised: the names come from a config file, and turning
  # arbitrary ones into atoms is unbounded.
  defp stats(%{"stats" => %{} = stats}, _findings), do: stats
  defp stats(_document, findings), do: %{"finding_count" => length(findings)}

  defp summary(%{"summary" => summary}, _findings, _status) when is_binary(summary), do: summary
  defp summary(_document, [], status), do: fallback_summary(status)

  defp summary(_document, findings, _status) do
    count = length(findings)

    "#{count} finding#{if count == 1, do: "", else: "s"}"
  end

  defp fallback_summary(:ok), do: "Passed"
  defp fallback_summary(:error), do: "Failed (see output)"
end
