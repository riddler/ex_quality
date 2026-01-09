defmodule Quality.Tools do
  @moduledoc """
  Detects which quality tools are available in the project.

  Checks Mix.Project.config()[:deps] for tool packages and determines
  which stages should be enabled by default.

  ## Example

      Quality.Tools.detect()
      #=> %{
        credo: true,
        dialyzer: true,
        doctor: false,
        coverage: true,
        gettext: false,
        audit: true
      }

      Quality.Tools.available?(:credo)
      #=> true
  """

  @tool_packages %{
    credo: :credo,
    dialyzer: :dialyxir,
    doctor: :doctor,
    coverage: :excoveralls,
    gettext: :gettext,
    audit: :mix_audit
  }

  @doc """
  Returns a map of tool availability.

  Scans the project's dependencies to determine which quality
  checking tools are installed.
  """
  @spec detect() :: %{atom() => boolean()}
  def detect do
    deps = get_project_deps()

    Map.new(@tool_packages, fn {tool, package} ->
      {tool, has_dep?(deps, package)}
    end)
  end

  @doc """
  Checks if a specific tool is available.

  Returns false if the tool is not recognized or not installed.
  """
  @spec available?(atom()) :: boolean()
  def available?(tool) do
    detect()[tool] || false
  end

  defp get_project_deps do
    case Mix.Project.get() do
      nil -> []
      _module -> Mix.Project.config()[:deps] || []
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
