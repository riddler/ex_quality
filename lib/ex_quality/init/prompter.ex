defmodule ExQuality.Init.Prompter do
  @moduledoc """
  Handles user interaction for tool selection.

  Provides an interactive prompt showing available tools with descriptions,
  marks already installed and recommended tools, and allows users to select
  which tools to install.
  """

  @tool_descriptions %{
    credo: "Static code analysis - finds bugs and code smells",
    dialyzer: "Type checking - catches type errors",
    doctor: "Documentation coverage - ensures code is documented",
    coverage: "Test coverage tracking with ExCoveralls",
    audit: "Security vulnerability scanning for dependencies",
    gettext: "Internationalization and translation management"
  }

  @doc """
  Prompts user to select which tools to install.

  Pre-selects recommended tools, allows user to customize selections via
  comma-separated input. Pressing Enter accepts the defaults.

  ## Parameters

  - `existing` - Map of tool availability from ExQuality.Tools.detect/0
  - `recommended` - List of tools to pre-select

  ## Returns

  List of tools the user wants to install (excluding already installed tools)
  """
  @spec prompt_for_tools(%{atom() => boolean()}, [atom()]) :: [atom()]
  def prompt_for_tools(existing, recommended) do
    Mix.shell().info("\nSelect quality tools to install:")
    Mix.shell().info("(Press Enter to accept defaults, or type tool names separated by commas)\n")

    # Show available tools with recommendations
    available_tools = [:credo, :dialyzer, :doctor, :coverage, :audit, :gettext]

    Enum.each(available_tools, fn tool ->
      status =
        cond do
          existing[tool] -> "✓ installed"
          Enum.member?(recommended, tool) -> "* recommended"
          true -> "  "
        end

      desc = @tool_descriptions[tool]
      Mix.shell().info("  [#{status}] #{tool} - #{desc}")
    end)

    Mix.shell().info("\nRecommended: #{format_list(recommended)}")

    # Prompt for input
    input =
      Mix.shell()
      |> prompt_with_default("Tools to install (or Enter for recommended)")
      |> String.trim()

    parse_tool_selection(input, existing, recommended)
  end

  # Private functions

  defp prompt_with_default(shell, message) do
    shell.prompt("#{message}: ")
  end

  defp parse_tool_selection("", existing, recommended) do
    # User pressed Enter - use recommended tools that aren't already installed
    recommended
    |> Enum.reject(fn tool -> existing[tool] end)
  end

  defp parse_tool_selection(input, existing, _recommended) do
    # Parse comma-separated tool names
    input
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.map(&parse_tool_name/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.reject(fn tool -> existing[tool] end)
    |> Enum.filter(&valid_tool?/1)
    |> case do
      [] ->
        Mix.shell().error("No valid tools selected. Please try again.")
        []

      tools ->
        tools
    end
  end

  defp parse_tool_name(name) do
    try do
      String.to_existing_atom(name)
    rescue
      ArgumentError ->
        Mix.shell().error("Unknown tool: #{name}")
        nil
    end
  end

  defp valid_tool?(tool) do
    tool in [:credo, :dialyzer, :doctor, :coverage, :audit, :gettext]
  end

  defp format_list(tools) do
    tools |> Enum.map(&to_string/1) |> Enum.join(", ")
  end
end
