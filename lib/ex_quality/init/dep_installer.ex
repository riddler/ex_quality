defmodule ExQuality.Init.DepInstaller do
  @moduledoc """
  Adds dependencies to mix.exs programmatically.

  Uses line-based insertion to preserve formatting and comments.
  Validates syntax after editing to ensure correctness.
  """

  @doc """
  Adds dependencies to mix.exs.

  Inserts new deps immediately after :ex_quality dependency (or at end of deps list).
  Creates a backup at mix.exs.backup before modifying.

  ## Returns

  - `:ok` on success
  - `{:error, reason}` on failure
  """
  @spec add_dependencies(%{atom() => {atom(), String.t()}}) :: :ok | {:error, String.t()}
  def add_dependencies(versions) when map_size(versions) == 0, do: :ok

  def add_dependencies(versions) do
    mix_exs_path = "mix.exs"

    if File.exists?(mix_exs_path) do
      # Read current content
      original_content = File.read!(mix_exs_path)

      # Find insertion point and build new deps
      do_add_dependencies(original_content, versions, mix_exs_path)
    else
      {:error, "mix.exs not found in current directory"}
    end
  end

  defp do_add_dependencies(original_content, versions, mix_exs_path) do
    case find_insertion_point(original_content) do
      {:ok, line_num, indent} ->
        new_deps = build_dep_lines(versions, indent)
        modified_content = insert_lines(original_content, line_num, new_deps)

        # Validate syntax before writing
        case Code.string_to_quoted(modified_content) do
          {:ok, _ast} ->
            # Backup original
            File.write!("#{mix_exs_path}.backup", original_content)

            # Write modified
            File.write!(mix_exs_path, modified_content)

            Mix.shell().info("✓ Added #{map_size(versions)} dependencies to mix.exs")
            Mix.shell().info("  (Backup saved to mix.exs.backup)")
            :ok

          {:error, _} ->
            {:error, "Syntax validation failed after editing mix.exs"}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Finds the line number where new deps should be inserted.

  ## Strategy

  1. Look for :ex_quality dependency line
  2. Insert immediately BEFORE it (so new deps have commas and ex_quality comma is optional)
  3. If not found, insert at end of deps function (before closing bracket)

  ## Returns

  - `{:ok, line_number, indentation_string}` on success
  - `{:error, reason}` on failure
  """
  @spec find_insertion_point(String.t()) ::
          {:ok, non_neg_integer(), String.t()} | {:error, String.t()}
  def find_insertion_point(content) do
    lines = String.split(content, "\n")

    # Strategy 1: Find :ex_quality line
    case find_quality_dep_line(lines) do
      {:ok, line_num, indent} ->
        {:ok, line_num, indent}

      :not_found ->
        # Strategy 2: Find end of deps function
        find_deps_end_line(lines)
    end
  end

  @doc """
  Extracts indentation from a line.

  ## Examples

      extract_indent("      {:credo, \"~> 1.7\"}")
      #=> "      "

      extract_indent("\\t\\t{:dialyxir, \"~> 1.4\"}")
      #=> "\\t\\t"
  """
  @spec extract_indent(String.t()) :: String.t()
  def extract_indent(line) do
    case Regex.run(~r/^(\s*)/, line) do
      [_, spaces] -> spaces
      _ -> "      "
    end
  end

  @doc """
  Builds dependency lines to insert.

  Uses recommended installation options from each tool's documentation.

  Format:
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false},
      {:excoveralls, "~> 0.18", only: :test},
  """
  @spec build_dep_lines(%{atom() => {atom(), String.t()}}, String.t()) :: [String.t()]
  def build_dep_lines(versions, indent) do
    versions
    |> Enum.map(fn {tool, {package, version}} ->
      build_dep_line(tool, package, version, indent)
    end)
  end

  @doc """
  Inserts lines into content at the specified line number.

  ## Examples

      insert_lines("line1\\nline2\\nline3", 2, ["new1", "new2"])
      #=> "line1\\nline2\\nnew1\\nnew2\\nline3"
  """
  @spec insert_lines(String.t(), non_neg_integer(), [String.t()]) :: String.t()
  def insert_lines(content, line_num, new_lines) do
    lines = String.split(content, "\n")

    {before, after_lines} = Enum.split(lines, line_num)

    (before ++ new_lines ++ after_lines)
    |> Enum.join("\n")
  end

  # Private functions

  defp find_quality_dep_line(lines) do
    lines
    |> Enum.with_index(1)
    |> Enum.find_value(fn {line, idx} ->
      if String.match?(line, ~r/\{:ex_quality,/) do
        indent = extract_indent(line)
        # Insert BEFORE ex_quality line (idx - 1) so new deps have trailing commas
        {:ok, idx - 1, indent}
      end
    end)
    |> case do
      nil -> :not_found
      result -> result
    end
  end

  defp find_deps_end_line(lines) do
    # Find the deps function, then find its closing bracket
    deps_start =
      Enum.find_index(lines, fn line ->
        String.match?(line, ~r/defp\s+deps\s+do/)
      end)

    case deps_start do
      nil ->
        {:error, "Could not find deps function in mix.exs"}

      start_idx ->
        # Find the first closing bracket after deps function
        # Look for a line that starts with spaces/tabs followed by ]
        end_line =
          lines
          |> Enum.drop(start_idx + 1)
          |> Enum.with_index(start_idx + 2)
          |> Enum.find(fn {line, _idx} ->
            String.match?(line, ~r/^\s+\]/)
          end)

        case end_line do
          {line, idx} ->
            indent = extract_indent(line)
            # Insert before the closing bracket
            {:ok, idx - 1, indent}

          nil ->
            {:error, "Could not find end of deps list in mix.exs"}
        end
    end
  end

  # Tool-specific recommended installation options
  # Based on each tool's official documentation and best practices
  #
  # Summary:
  # - credo:        only: [:dev, :test], runtime: false  (static analysis in dev/test)
  # - dialyxir:     only: [:dev], runtime: false         (type checking in dev only)
  # - excoveralls:  only: :test                          (coverage in test only)
  # - doctor:       only: :dev                           (doc checks in dev only)
  # - mix_audit:    only: [:dev, :test], runtime: false  (security checks dev/test)
  # - gettext:      (no restrictions - runtime dependency for translations)

  defp build_dep_line(:credo, package, version, indent) do
    # Credo: dev and test environments, no runtime
    "#{indent}{:#{package}, \"#{version}\", only: [:dev, :test], runtime: false},"
  end

  defp build_dep_line(:dialyzer, package, version, indent) do
    # Dialyxir: dev only (type checking during development)
    "#{indent}{:#{package}, \"#{version}\", only: [:dev], runtime: false},"
  end

  defp build_dep_line(:coverage, package, version, indent) do
    # ExCoveralls: test only (coverage analysis)
    "#{indent}{:#{package}, \"#{version}\", only: :test},"
  end

  defp build_dep_line(:doctor, package, version, indent) do
    # Doctor: dev only (documentation checks during development)
    "#{indent}{:#{package}, \"#{version}\", only: :dev},"
  end

  defp build_dep_line(:audit, package, version, indent) do
    # mix_audit: dev and test (security checks)
    "#{indent}{:#{package}, \"#{version}\", only: [:dev, :test], runtime: false},"
  end

  defp build_dep_line(:gettext, package, version, indent) do
    # Gettext: runtime dependency (needed for translations)
    "#{indent}{:#{package}, \"#{version}\"},"
  end

  defp build_dep_line(_tool, package, version, indent) do
    # Default: dev/test only, no runtime
    "#{indent}{:#{package}, \"#{version}\", only: [:dev, :test], runtime: false},"
  end
end
