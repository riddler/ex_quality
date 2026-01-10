defmodule ExQuality.Init.ToolSetup do
  @moduledoc """
  Runs tool-specific setup commands after dependencies are installed.

  Each tool may have initialization requirements like generating config files
  or running setup tasks. This module handles those tool-specific steps.
  """

  @doc """
  Sets up all tools in the list.

  Runs setup commands sequentially (not parallel, as they may conflict).
  Continues with remaining tools even if one fails.
  """
  @spec setup_all([atom()]) :: :ok
  def setup_all(tools) do
    Enum.each(tools, &setup_tool/1)
  end

  @spec setup_tool(atom()) :: :ok
  defp setup_tool(:credo) do
    Mix.shell().info("  Setting up Credo...")

    # Run: mix credo gen.config
    case System.cmd("mix", ["credo", "gen.config"], stderr_to_stdout: true) do
      {_output, 0} ->
        Mix.shell().info("    ✓ Created .credo.exs")
        :ok

      {output, _} ->
        # Credo might fail if .credo.exs already exists
        if String.contains?(output, "already exists") or String.contains?(output, ".credo.exs") do
          Mix.shell().info("    ○ .credo.exs already exists")
          :ok
        else
          Mix.shell().error("    Warning: Credo setup failed")
          :ok
        end
    end
  end

  defp setup_tool(:dialyzer) do
    Mix.shell().info("  Setting up Dialyzer...")
    Mix.shell().info("    ○ No initialization needed (PLTs will be built on first run)")
    :ok
  end

  defp setup_tool(:doctor) do
    Mix.shell().info("  Setting up Doctor...")
    Mix.shell().info("    ○ Add doctor config to mix.exs if needed:")
    Mix.shell().info("      In your project/0 function, add:")
    Mix.shell().info("")
    Mix.shell().info("      docs: [")
    Mix.shell().info("        extras: [\"README.md\"],")
    Mix.shell().info("        doctor: [")
    Mix.shell().info("          min_module_doc_coverage: 80,")
    Mix.shell().info("          min_function_doc_coverage: 50")
    Mix.shell().info("        ]")
    Mix.shell().info("      ]")
    Mix.shell().info("")
    :ok
  end

  defp setup_tool(:coverage) do
    Mix.shell().info("  Setting up ExCoveralls...")

    # Check if coveralls.json exists
    if File.exists?("coveralls.json") do
      Mix.shell().info("    ○ coveralls.json already exists")
    else
      create_coveralls_config()
    end

    :ok
  end

  defp setup_tool(:audit) do
    Mix.shell().info("  Setting up mix_audit...")
    Mix.shell().info("    ○ No initialization needed")
    :ok
  end

  defp setup_tool(:gettext) do
    Mix.shell().info("  Setting up Gettext...")

    # Check if gettext is already set up (priv/gettext exists)
    if File.dir?("priv/gettext") do
      Mix.shell().info("    ○ Gettext already configured")
    else
      Mix.shell().info("    ○ Run 'mix gettext.merge priv/gettext' to initialize translations")
    end

    :ok
  end

  defp setup_tool(unknown) do
    Mix.shell().info("  Skipping setup for #{unknown} (unknown tool)")
    :ok
  end

  defp create_coveralls_config do
    config = """
    {
      "coverage_options": {
        "minimum_coverage": 80,
        "treat_no_relevant_lines_as_covered": true
      },
      "skip_files": [
        "test/",
        "lib/mix/tasks/"
      ]
    }
    """

    File.write!("coveralls.json", config)
    Mix.shell().info("    ✓ Created coveralls.json")
  end
end
