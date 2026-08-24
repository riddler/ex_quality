defmodule ExQuality.Tools do
  @moduledoc """
  Detects which quality tools are available in the project.

  Checks the project's declared dependencies for tool packages and determines
  which stages should be enabled by default.

  In an umbrella, the root `mix.exs` usually declares no dependencies, so the
  root's deps are unioned with every child app's (`ExQuality.Umbrella`).
  Reading only the root would report every tool as missing and quietly run a
  fraction of the checks.

  ## Example

      ExQuality.Tools.detect()
      #=> %{
        credo: true,
        dialyzer: true,
        doctor: false,
        docs: true,
        coverage: true,
        native_coverage: false,
        gettext: false,
        audit: true,
        sobelow: false
      }

      ExQuality.Tools.available?(:credo)
      #=> true

  `:native_coverage` is the exception: it is not a package but the absence of
  one. Elixir has shipped `mix test --cover` since 1.11, so a project without
  `:excoveralls` still has a coverage tool, and the stage needs to know which of
  the two it is talking to.
  """

  @tool_packages %{
    credo: :credo,
    dialyzer: :dialyxir,
    doctor: :doctor,
    docs: :ex_doc,
    coverage: :excoveralls,
    gettext: :gettext,
    audit: :mix_audit,
    sobelow: :sobelow
  }

  @doc """
  Returns a map of tool availability.

  Scans the project's dependencies to determine which quality
  checking tools are installed.
  """
  @spec detect() :: %{atom() => boolean()}
  def detect do
    deps = get_project_deps()

    detected =
      Map.new(@tool_packages, fn {tool, package} ->
        {tool, has_dep?(deps, package)}
      end)

    Map.put(detected, :native_coverage, not detected.coverage)
  end

  @doc """
  Checks if a specific tool is available.

  Returns false if the tool is not recognized or not installed.
  """
  @spec available?(atom()) :: boolean()
  def available?(tool) do
    detect()[tool] || false
  end

  @doc """
  Returns the package a tool is detected from, or `nil` for an unknown tool.

  ## Examples

      ExQuality.Tools.package(:dialyzer)
      #=> :dialyxir
  """
  @spec package(atom()) :: atom() | nil
  def package(tool), do: Map.get(@tool_packages, tool)

  defp get_project_deps do
    case Mix.Project.get() do
      nil -> []
      _module -> (Mix.Project.config()[:deps] || []) ++ ExQuality.Umbrella.child_deps()
    end
  end

  defp has_dep?(deps, package) do
    Enum.any?(deps, fn
      {^package, _} -> true
      {^package, _, _} -> true
      _ -> false
    end)
  end
end
