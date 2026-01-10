defmodule ExQuality.Init.VersionResolver do
  @moduledoc """
  Resolves latest package versions from hex.pm.

  Uses `mix hex.info <package>` to fetch version information and parses
  the recommended version string from the output.
  """

  @tool_packages %{
    credo: :credo,
    dialyzer: :dialyxir,
    doctor: :doctor,
    coverage: :excoveralls,
    audit: :mix_audit,
    gettext: :gettext
  }

  @doc """
  Fetches latest versions for the given tools.

  Returns a map of tool -> {package_name, version_spec}.

  ## Examples

      fetch_versions([:credo, :dialyzer])
      #=> %{
        credo: {:credo, "~> 1.7"},
        dialyzer: {:dialyxir, "~> 1.4"}
      }
  """
  @spec fetch_versions([atom()]) :: %{atom() => {atom(), String.t()}}
  def fetch_versions(tools) do
    tools
    |> Enum.map(fn tool ->
      package = @tool_packages[tool]
      version = fetch_version(package)
      {tool, {package, version}}
    end)
    |> Map.new()
  end

  @spec fetch_version(atom()) :: String.t()
  defp fetch_version(package) do
    case System.cmd("mix", ["hex.info", to_string(package)], stderr_to_stdout: true) do
      {output, 0} ->
        parse_version_from_output(output)

      {_output, _exit_code} ->
        Mix.shell().error("Warning: Could not fetch version for #{package}, using fallback")
        "~> 0.1"
    end
  end

  @doc """
  Parses version from hex.info output.

  Looks for the Config line which contains the recommended version string.

  ## Examples

      output = \"\"\"
      Config: {:credo, "~> 1.7"}
      Locked version: 1.7.15
      Releases: 1.7.15, 1.7.14, ...
      \"\"\"

      parse_version_from_output(output)
      #=> "~> 1.7"

  Falls back to parsing the Releases line if Config is not found,
  and uses "~> 0.1" as a last resort.
  """
  @spec parse_version_from_output(String.t()) :: String.t()
  def parse_version_from_output(output) do
    # Look for line like: Config: {:credo, "~> 1.7"}
    case Regex.run(~r/Config:\s*\{:?\w+,\s*"([^"]+)"\}/, output) do
      [_, version] ->
        version

      nil ->
        # Fallback: try to parse from "Releases: X.Y.Z, ..." line
        case Regex.run(~r/Releases:\s*(\d+\.\d+)/, output) do
          [_, major_minor] ->
            "~> #{major_minor}"

          nil ->
            Mix.shell().error("Warning: Could not parse version from hex.info output")
            "~> 0.1"
        end
    end
  end
end
