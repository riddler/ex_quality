defmodule Mix.Tasks.Quality.Init do
  @shortdoc "Initialize quality tooling for your project"

  @moduledoc """
  Sets up ExQuality and recommended quality tools in your project.

  ## What it does

  1. Detects which tools are already installed
  2. Prompts for which tools to add (pre-selects credo, dialyzer, excoveralls)
  3. Fetches latest versions from hex.pm
  4. Adds dependencies to mix.exs near the :ex_quality dependency
  5. Runs `mix deps.get`
  6. Runs tool-specific setup commands
  7. Creates .quality.exs config file (optional)

  ## Usage

      mix quality.init
      mix quality.init --skip-prompts  # Use defaults
      mix quality.init --no-config     # Don't create .quality.exs
      mix quality.init --all           # Install all tools

  ## Available Tools

  - credo: Static code analysis
  - dialyzer (dialyxir): Type checking
  - doctor: Documentation coverage
  - coverage (excoveralls): Test coverage
  - audit (mix_audit): Security vulnerability scanning
  - gettext: Internationalization

  ## Options

  - `--skip-prompts` - Use recommended defaults without prompting
  - `--no-config` - Don't create .quality.exs config file
  - `--all` - Install all available tools
  """

  use Mix.Task

  alias ExQuality.Init.DepInstaller
  alias ExQuality.Init.Prompter
  alias ExQuality.Init.ToolSetup
  alias ExQuality.Init.VersionResolver
  alias ExQuality.Tools

  @switches [
    skip_prompts: :boolean,
    no_config: :boolean,
    all: :boolean
  ]

  @recommended_tools [:credo, :dialyzer, :coverage]

  @doc """
  Runs the quality.init task to set up ExQuality in your project.

  Accepts command-line arguments to customize behavior.
  """
  @spec run([String.t()]) :: :ok
  def run(args) do
    {opts, _remaining} = OptionParser.parse!(args, switches: @switches)

    Mix.shell().info("Initializing ExQuality for your project...\n")

    # Step 1: Detect existing tools
    existing = Tools.detect()
    display_existing_tools(existing)

    # Step 2: Determine which tools to install
    tools_to_install = select_tools(existing, opts)

    if tools_to_install == [] do
      Mix.shell().info("\n✓ All recommended tools already installed!")
      maybe_create_config(opts)
      :ok
    else
      # Step 3: Fetch latest versions
      Mix.shell().info("\nFetching latest versions from hex.pm...")
      versions = VersionResolver.fetch_versions(tools_to_install)

      # Step 4: Add dependencies to mix.exs
      Mix.shell().info("Adding dependencies to mix.exs...")

      case DepInstaller.add_dependencies(versions) do
        :ok ->
          # Step 4b: Configure project settings (like test_coverage)
          configure_project_settings(tools_to_install)

          # Step 5: Install dependencies
          Mix.shell().info("\nRunning mix deps.get...")
          run_deps_get()

          # Step 6: Run tool-specific setup
          Mix.shell().info("\nSetting up tools...")
          ToolSetup.setup_all(tools_to_install)

          # Step 7: Create config file
          maybe_create_config(opts)

          display_success(tools_to_install)

        {:error, reason} ->
          Mix.raise("Failed to add dependencies: #{reason}")
      end
    end
  end

  defp select_tools(existing, opts) do
    cond do
      opts[:all] ->
        # Install all missing tools
        all_tools() |> Enum.reject(fn tool -> existing[tool] end)

      opts[:skip_prompts] ->
        # Install recommended missing tools
        @recommended_tools |> Enum.reject(fn tool -> existing[tool] end)

      true ->
        # Interactive prompt
        Prompter.prompt_for_tools(existing, @recommended_tools)
    end
  end

  defp all_tools, do: [:credo, :dialyzer, :doctor, :coverage, :audit, :gettext]

  defp display_existing_tools(existing) do
    installed = existing |> Enum.filter(fn {_k, v} -> v end) |> Enum.map(&elem(&1, 0))

    if installed != [] do
      Mix.shell().info("Already installed: #{format_tool_list(installed)}")
    else
      Mix.shell().info("No quality tools detected in mix.exs")
    end
  end

  defp format_tool_list(tools) do
    Enum.map_join(tools, ", ", &to_string/1)
  end

  defp configure_project_settings(tools) do
    if :coverage in tools do
      add_test_coverage_config()
    end
  end

  defp add_test_coverage_config do
    mix_exs_path = "mix.exs"
    content = File.read!(mix_exs_path)

    # Check if test_coverage is already configured
    if String.contains?(content, "test_coverage:") or
         String.contains?(content, "coveralls:") do
      Mix.shell().info("  ○ Coverage configuration already present in mix.exs")
      :ok
    else
      # Find the project function and add test_coverage configuration
      case add_test_coverage_to_project(content) do
        {:ok, modified_content} ->
          File.write!(mix_exs_path, modified_content)
          Mix.shell().info("  ✓ Added test_coverage configuration to mix.exs")
          :ok

        {:error, reason} ->
          Mix.shell().error("  Warning: Could not add test_coverage config: #{reason}")
          Mix.shell().info("  Please add manually: test_coverage: [tool: ExCoveralls]")
          :ok
      end
    end
  end

  defp add_test_coverage_to_project(content) do
    lines = String.split(content, "\n")

    # Find the project function's opening bracket
    case find_project_bracket(lines) do
      {:ok, bracket_line} ->
        # Insert test_coverage and preferred_cli_env config after the opening bracket
        indent = extract_indent_from_project(lines, bracket_line)

        coverage_config = """
        #{indent}test_coverage: [tool: ExCoveralls],
        #{indent}preferred_cli_env: [
        #{indent}  coveralls: :test,
        #{indent}  "coveralls.detail": :test,
        #{indent}  "coveralls.post": :test,
        #{indent}  "coveralls.html": :test
        #{indent}],\
        """

        new_lines =
          List.update_at(lines, bracket_line, fn line ->
            line <> "\n" <> coverage_config
          end)

        {:ok, Enum.join(new_lines, "\n")}

      :not_found ->
        {:error, "Could not find project function"}
    end
  end

  defp find_project_bracket(lines) do
    # Find "def project do" line
    project_line =
      Enum.find_index(lines, fn line ->
        String.match?(line, ~r/def\s+project\s+do/)
      end)

    case project_line do
      nil ->
        :not_found

      idx ->
        # Find the opening bracket [ after "def project do"
        bracket_line =
          lines
          |> Enum.drop(idx + 1)
          |> Enum.with_index(idx + 1)
          |> Enum.find(fn {line, _idx} ->
            String.match?(line, ~r/^\s+\[/)
          end)

        case bracket_line do
          {_line, line_idx} -> {:ok, line_idx}
          nil -> :not_found
        end
    end
  end

  defp extract_indent_from_project(lines, bracket_line) do
    # Look at the next line after [ to get the indentation level
    next_line = Enum.at(lines, bracket_line + 1, "")

    case Regex.run(~r/^(\s*)/, next_line) do
      [_, spaces] -> spaces
      _ -> "      "
    end
  end

  defp run_deps_get do
    {_output, exit_code} = System.cmd("mix", ["deps.get"], stderr_to_stdout: true)

    if exit_code != 0 do
      Mix.raise("mix deps.get failed")
    end
  end

  defp maybe_create_config(opts) do
    unless opts[:no_config] do
      if File.exists?(".quality.exs") do
        Mix.shell().info("\n✓ .quality.exs already exists")
      else
        create_quality_config()
      end
    end
  end

  defp create_quality_config do
    template = """
    # Quality Configuration
    #
    # This file allows you to customize the behavior of `mix quality`.
    #
    # Configuration is merged in this order (later wins):
    # 1. Defaults
    # 2. Auto-detected tool availability
    # 3. This file (.quality.exs)
    # 4. CLI arguments (--quick, --skip-*, etc.)

    [
      # Global options
      # quick: false,  # Skip dialyzer and coverage enforcement

      # Compilation options
      # compile: [
      #   warnings_as_errors: true
      # ],

      # Credo static analysis
      # credo: [
      #   enabled: :auto,  # :auto | true | false
      #   strict: true,
      #   all: false
      # ],

      # Dialyzer type checking
      # dialyzer: [
      #   enabled: :auto  # :auto | true | false
      # ],

      # Doctor documentation coverage
      # doctor: [
      #   enabled: :auto,  # :auto | true | false
      #   summary_only: false
      # ],

      # Gettext translation completeness
      # gettext: [
      #   enabled: :auto  # :auto | true | false
      # ],

      # Dependencies (unused deps and security audit)
      # dependencies: [
      #   enabled: :auto,
      #   check_unused: true,
      #   audit: :auto  # Requires mix_audit package
      # ]

      # Note: Coverage threshold is configured in coveralls.json or mix.exs
    ]
    """

    File.write!(".quality.exs", template)
    Mix.shell().info("\n✓ Created .quality.exs configuration file")
  end

  defp display_success(tools) do
    Mix.shell().info("\n✅ ExQuality initialization complete!")
    Mix.shell().info("\nAdded tools: #{format_tool_list(tools)}")
    Mix.shell().info("\nNext steps:")
    Mix.shell().info("  1. Review the changes to mix.exs")
    Mix.shell().info("  2. Customize .quality.exs if needed")
    Mix.shell().info("  3. Run `mix quality` to check your code")
  end
end
