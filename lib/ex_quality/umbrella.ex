defmodule ExQuality.Umbrella do
  @moduledoc """
  Umbrella awareness: which child apps exist, where they live, and what they
  declare.

  An umbrella root's `mix.exs` usually declares no dependencies of its own, so
  anything that reads only the root project sees an empty list and concludes
  that no quality tools are installed. Every function here folds the child apps
  in, and answers `false`, `%{}` or `nil` for a single-app project, so callers
  never branch on the project shape themselves.

  ## Example

      ExQuality.Umbrella.apps_paths()
      #=> %{web: "apps/web", core: "apps/core"}

      ExQuality.Umbrella.app_for_path("apps/web/lib/user.ex")
      #=> :web
  """

  @doc """
  Returns true when the current project is an umbrella.

  Returns false when there is no project at all, so this is safe to call
  outside a Mix project.
  """
  @spec umbrella?() :: boolean()
  def umbrella? do
    Mix.Project.get() != nil and Mix.Project.umbrella?()
  end

  @doc """
  Returns the child apps as a map of app name to path, relative to the
  umbrella root.

  Returns an empty map for a single-app project.
  """
  @spec apps_paths() :: %{atom() => String.t()}
  def apps_paths do
    if umbrella?() do
      Mix.Project.apps_paths() || %{}
    else
      %{}
    end
  end

  @doc """
  Returns the umbrella app a path belongs to, or `nil` when it belongs to none.

  Pass `apps` to avoid re-reading the project once per path, which is what
  callers tagging a list of findings should do.

      iex> apps = %{web: "apps/web"}
      iex> ExQuality.Umbrella.app_for_path("apps/web/lib/user.ex", apps)
      :web

      iex> ExQuality.Umbrella.app_for_path("lib/user.ex", %{web: "apps/web"})
      nil
  """
  @spec app_for_path(String.t() | nil, %{atom() => String.t()}) :: atom() | nil
  def app_for_path(path, apps \\ apps_paths())

  def app_for_path(nil, _apps), do: nil

  def app_for_path(path, apps) do
    segments = path |> Path.relative_to_cwd() |> Path.split()

    Enum.find_value(apps, fn {app, app_path} ->
      if List.starts_with?(segments, Path.split(app_path)), do: app
    end)
  end

  @doc """
  Returns the dependency specs declared by every child app, in `mix.exs` form.

  The result is cached for the lifetime of the VM, because reading it evaluates
  each child's `mix.exs`. A child whose `mix.exs` cannot be evaluated
  contributes nothing rather than failing the run: the compile stage reports
  that problem with a far better message than tool detection could.
  """
  @spec child_deps() :: [tuple()]
  def child_deps, do: app_deps() |> Map.values() |> List.flatten()

  @doc """
  Returns the dependency specs declared by each child app, keyed by app.

  Use this over `child_deps/0` when *which* app declares a dependency matters,
  as it does for a stage that only has something to say about the apps using a
  given library.

  Returns an empty map for a single-app project. Shares `child_deps/0`'s cache.
  """
  @spec app_deps() :: %{atom() => [tuple()]}
  def app_deps do
    case :persistent_term.get(cache_key(), :miss) do
      :miss ->
        deps = read_child_deps()
        :persistent_term.put(cache_key(), deps)
        deps

      deps ->
        deps
    end
  end

  @doc """
  Drops the cached child dependencies. Intended for tests.
  """
  @spec reset_cache() :: :ok
  def reset_cache do
    _erased? = :persistent_term.erase(cache_key())
    :ok
  end

  defp cache_key, do: {__MODULE__, :child_deps, Mix.Project.get()}

  defp read_child_deps do
    Map.new(apps_paths(), fn {app, path} -> {app, read_deps(app, path)} end)
  end

  defp read_deps(app, path) do
    Mix.Project.in_project(app, path, fn _module -> Mix.Project.config()[:deps] || [] end)
  rescue
    _error -> []
  end
end
