defmodule ExQuality.Custom do
  @moduledoc """
  Project-defined stages, declared in `.quality.exs` under `custom:`.

  A project with a house check, a schema linter, a custom mix task or a shell
  script gate could have ExQuality's parallelism, timing, report and printer,
  or it could have its own check, but not both. Custom stages are the way to
  have both, and a check that runs inside `mix quality` is a check the JSON
  report can route on.

  Two layers, one mechanism:

      custom: [
        # A command. This is the case most projects want.
        [
          key: :nullability,
          name: "Nullability",
          command: "mix",
          args: ["schema.nullability", "--format", "json"],
          env: [{"MIX_ENV", "test"}],
          kind: :reader
        ],

        # A module, for anything the command form cannot express.
        [key: :house_rules, name: "House rules", module: MyApp.Quality.HouseRules]
      ]

  Every entry is a keyword list with `key` and `name`, plus either `module` or
  `command`. Registration data lives in the entry rather than in callbacks on a
  module so that the config file alone says what a run will contain: a stage
  that only announces itself once it has run cannot be reported as skipped, and
  a run that says nothing about a stage reads as a run where the stage passed.

  ## Module entries

  `module:` names a module exporting `run/1` and returning an
  `ExQuality.Stage.result()`, which is the contract every built-in stage
  already satisfies. It may also export `stage_kind/1`; a module that does not
  is a `:reader`. See `ExQuality.Stage`.

  ## Command entries

  `command:` is run by `ExQuality.Stages.Command`, which documents the options
  and the JSON finding contract.

  ## What custom stages are not for

  Filling gaps in built-in stages. Routing a second `mix credo` config through
  a custom command would work and would be a mistake: the output comes back as
  text instead of per-check findings, and per-check routing is the reason the
  JSON report exists. If a built-in stage cannot express something its tool
  supports, that is a bug in the stage.
  """

  alias ExQuality.Config
  alias ExQuality.Stage
  alias ExQuality.Stages.Command

  # Reserved so a custom stage cannot shadow a built-in one. A custom stage
  # named "Credo" that quietly replaced the real one is the same class of bug
  # as an aliased mix task: the run still reports Credo, and it is not credo.
  @builtin_keys [
    :format,
    :compile,
    :test,
    :credo,
    :dialyzer,
    :doctor,
    :gettext,
    :sobelow,
    :dependencies
  ]

  @builtin_names [
    "Format",
    "Compile",
    "Tests",
    "Credo",
    "Dialyzer",
    "Doctor",
    "Gettext",
    "Sobelow",
    "Dependencies"
  ]

  @kinds [:reader, :writer]
  @parse_modes [:json, :none]

  @doc """
  Returns the custom stage entries in a loaded config, in declaration order.

      iex> ExQuality.Custom.stages([])
      []
  """
  @spec stages(keyword()) :: [keyword()]
  def stages(config) do
    case Keyword.get(config, :custom, []) do
      entries when is_list(entries) -> entries
      _other -> []
    end
  end

  @doc """
  Returns whether an entry reads the build or writes to it.

  An entry that declares `kind:` is taken at its word. Otherwise a module entry
  is asked, via `ExQuality.Stage.kind/2`, and a command entry is a `:reader`.

      iex> ExQuality.Custom.kind([key: :a, name: "A", command: "true"], [])
      :reader
  """
  @spec kind(keyword(), keyword()) :: Stage.kind()
  def kind(entry, config) do
    case Keyword.fetch(entry, :kind) do
      {:ok, kind} -> kind
      :error -> module_kind(entry, config)
    end
  end

  defp module_kind(entry, config) do
    case Keyword.fetch(entry, :module) do
      {:ok, module} -> Stage.kind(module, config)
      :error -> :reader
    end
  end

  @doc """
  Returns the function that runs an entry, given the run's config.
  """
  @spec runner(keyword()) :: (keyword() -> Stage.result())
  def runner(entry) do
    case Keyword.fetch(entry, :module) do
      {:ok, module} -> &module.run/1
      :error -> fn _config -> Command.run(entry) end
    end
  end

  @doc """
  Returns why a custom stage will not run, or `nil` when it will.

  `--skip <key>` is read through `ExQuality.Config.skip_reason/2`, exactly as a
  built-in stage's switch is. `enabled: false` in the entry itself is the
  config-file spelling.
  """
  @spec skip_reason(keyword(), keyword()) :: String.t() | nil
  def skip_reason(config, entry) do
    case skip(config, entry) do
      nil -> nil
      {reason, _kind} -> reason
    end
  end

  @doc """
  Returns why a custom stage will not run and what kind of skip that is, or
  `nil` when it will run. The kinds are `ExQuality.Config.skip/2`'s: a switch
  is a `:run` skip, an `enabled: false` is a `:project` one.
  """
  @spec skip(keyword(), keyword()) :: {String.t(), Stage.skip_kind()} | nil
  def skip(config, entry) do
    cond do
      skip = Config.skip(config, Keyword.fetch!(entry, :key)) -> skip
      Keyword.get(entry, :enabled, true) == false -> {"disabled in .quality.exs", :project}
      true -> nil
    end
  end

  @doc """
  Raises unless every custom entry in `config` is well formed.

  Custom stages are the place a config file can be wrong in ways that silently
  weaken a run - a stage that never registers is a check nobody is told is not
  running - so this fails the run at load time and names the offending entry
  rather than letting it go quiet.
  """
  @spec validate!(keyword()) :: :ok
  def validate!(config) do
    entries = Keyword.get(config, :custom, [])

    unless is_list(entries) and Enum.all?(entries, &Keyword.keyword?/1) do
      Mix.raise(
        "custom: in .quality.exs must be a list of keyword lists, got: #{inspect(entries)}"
      )
    end

    Enum.each(entries, &validate_entry!/1)
    validate_unique!(entries)

    :ok
  end

  defp validate_unique!(entries) do
    entries
    |> Enum.map(&Keyword.get(&1, :key))
    |> Enum.frequencies()
    |> Enum.each(fn
      {key, count} when count > 1 -> raise_entry("duplicate custom stage key #{inspect(key)}", [])
      _unique -> :ok
    end)
  end

  defp validate_entry!(entry) do
    validate_key!(entry)
    validate_name!(entry)
    validate_implementation!(entry)
    validate_kind!(entry)
    validate_command_options!(entry)
  end

  defp validate_key!(entry) do
    case Keyword.fetch(entry, :key) do
      {:ok, key} when is_atom(key) and not is_nil(key) ->
        if key in @builtin_keys do
          raise_entry("key #{inspect(key)} is a built-in stage", entry)
        end

      {:ok, key} ->
        raise_entry("key must be an atom, got: #{inspect(key)}", entry)

      :error ->
        raise_entry("missing key:", entry)
    end
  end

  defp validate_name!(entry) do
    case Keyword.fetch(entry, :name) do
      {:ok, name} when is_binary(name) and name != "" ->
        if name in @builtin_names do
          raise_entry("name #{inspect(name)} is a built-in stage", entry)
        end

      {:ok, name} ->
        raise_entry("name must be a non-empty string, got: #{inspect(name)}", entry)

      :error ->
        raise_entry("missing name:", entry)
    end
  end

  defp validate_implementation!(entry) do
    case {Keyword.fetch(entry, :module), Keyword.fetch(entry, :command)} do
      {{:ok, _module}, {:ok, _command}} ->
        raise_entry("declares both module: and command:, which cannot both run", entry)

      {{:ok, module}, :error} ->
        validate_module!(module, entry)

      {:error, {:ok, command}} when is_binary(command) and command != "" ->
        :ok

      {:error, {:ok, command}} ->
        raise_entry("command must be a non-empty string, got: #{inspect(command)}", entry)

      {:error, :error} ->
        raise_entry("declares neither module: nor command:", entry)
    end
  end

  defp validate_module!(module, entry) when is_atom(module) do
    cond do
      not Code.ensure_loaded?(module) ->
        raise_entry("module #{inspect(module)} could not be loaded", entry)

      not function_exported?(module, :run, 1) ->
        raise_entry("module #{inspect(module)} does not export run/1", entry)

      true ->
        :ok
    end
  end

  defp validate_module!(module, entry) do
    raise_entry("module must be a module, got: #{inspect(module)}", entry)
  end

  defp validate_kind!(entry) do
    case Keyword.fetch(entry, :kind) do
      {:ok, kind} when kind in @kinds -> :ok
      {:ok, kind} -> raise_entry("kind must be :reader or :writer, got: #{inspect(kind)}", entry)
      :error -> :ok
    end
  end

  defp validate_command_options!(entry) do
    validate_args!(entry)
    validate_env!(entry)
    validate_parse!(entry)
    validate_skip_exit_code!(entry)
  end

  defp validate_args!(entry) do
    args = Keyword.get(entry, :args, [])

    unless is_list(args) and Enum.all?(args, &is_binary/1) do
      raise_entry("args must be a list of strings, got: #{inspect(args)}", entry)
    end
  end

  defp validate_env!(entry) do
    env = Keyword.get(entry, :env, [])

    valid? =
      is_list(env) and
        Enum.all?(env, fn
          {name, value} -> is_binary(name) and is_binary(value)
          _other -> false
        end)

    unless valid? do
      raise_entry("env must be a list of {name, value} string pairs, got: #{inspect(env)}", entry)
    end
  end

  defp validate_parse!(entry) do
    case Keyword.fetch(entry, :parse) do
      {:ok, mode} when mode in @parse_modes -> :ok
      {:ok, mode} -> raise_entry("parse must be :json or :none, got: #{inspect(mode)}", entry)
      :error -> :ok
    end
  end

  defp validate_skip_exit_code!(entry) do
    case Keyword.fetch(entry, :skip_exit_code) do
      {:ok, code} when is_integer(code) ->
        :ok

      {:ok, code} ->
        raise_entry("skip_exit_code must be an integer, got: #{inspect(code)}", entry)

      :error ->
        :ok
    end
  end

  @spec raise_entry(String.t(), keyword()) :: no_return()
  defp raise_entry(problem, []), do: Mix.raise("Invalid custom stage: #{problem}")

  defp raise_entry(problem, entry) do
    Mix.raise("Invalid custom stage: #{problem}\n\n    #{inspect(entry)}\n")
  end
end
