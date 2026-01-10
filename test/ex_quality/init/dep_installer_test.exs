defmodule ExQuality.Init.DepInstallerTest do
  use ExUnit.Case, async: true

  alias ExQuality.Init.DepInstaller

  describe "find_insertion_point/1" do
    test "finds :ex_quality line" do
      content = ~S"""
defmodule TestProject.MixProject do
  defp deps do
    [
      {:ex_quality, "~> 0.1", only: :dev},
      {:jason, "~> 1.4"}
    ]
  end
end
"""

      # Should insert BEFORE ex_quality (line 3, before line 4)
      assert {:ok, 3, indent} = DepInstaller.find_insertion_point(content)
      # Should have captured indentation (6 spaces for items inside list)
      assert indent == "      "
    end

    test "falls back to end of deps list if :ex_quality not found" do
      content = ~S"""
defmodule TestProject.MixProject do
  defp deps do
    [
      {:jason, "~> 1.4"}
    ]
  end
end
"""

      # Should insert before the closing ]
      assert {:ok, line_num, indent} = DepInstaller.find_insertion_point(content)
      assert line_num == 4
      # Indentation is extracted from the closing bracket line (4 spaces)
      assert indent == "    "
    end

    test "extracts correct indentation from existing deps" do
      content = ~S"""
defp deps do
  [
    {:ex_quality, "~> 0.1"}
  ]
end
"""

      assert {:ok, line, indent} = DepInstaller.find_insertion_point(content)
      # Should insert before ex_quality (line 2, before line 3)
      assert line == 2
      # Indentation is extracted from the ex_quality line (4 spaces)
      assert indent == "    "
    end

    test "handles tab indentation" do
      content = """
      defp deps do
      \t[
      \t\t{:ex_quality, "~> 0.1"}
      \t]
      end
      """

      assert {:ok, _line, indent} = DepInstaller.find_insertion_point(content)
      assert indent == "\t\t"
    end

    test "returns error if deps function not found" do
      content = """
      defmodule TestProject.MixProject do
        def project do
          [app: :test]
        end
      end
      """

      assert {:error, message} = DepInstaller.find_insertion_point(content)
      assert message =~ "Could not find deps function"
    end
  end

  describe "extract_indent/1" do
    test "extracts spaces" do
      assert DepInstaller.extract_indent("      {:credo, \"~> 1.7\"}") == "      "
    end

    test "extracts tabs" do
      assert DepInstaller.extract_indent("\t\t{:dialyxir, \"~> 1.4\"}") == "\t\t"
    end

    test "handles mixed whitespace" do
      assert DepInstaller.extract_indent("  \t  {:package}") == "  \t  "
    end

    test "handles no indentation" do
      assert DepInstaller.extract_indent("{:package}") == ""
    end

    test "uses default if no match" do
      # This shouldn't happen in practice, but test the fallback
      assert is_binary(DepInstaller.extract_indent(""))
    end
  end

  describe "build_dep_lines/2" do
    test "formats credo with dev and test environments" do
      versions = %{credo: {:credo, "~> 1.7"}}
      lines = DepInstaller.build_dep_lines(versions, "    ")

      assert length(lines) == 1
      [line] = lines
      assert line == "    {:credo, \"~> 1.7\", only: [:dev, :test], runtime: false},"
    end

    test "formats dialyxir with dev only" do
      versions = %{dialyzer: {:dialyxir, "~> 1.4"}}
      lines = DepInstaller.build_dep_lines(versions, "    ")

      [line] = lines
      assert line == "    {:dialyxir, \"~> 1.4\", only: [:dev], runtime: false},"
    end

    test "formats excoveralls with test only" do
      versions = %{coverage: {:excoveralls, "~> 0.18"}}
      lines = DepInstaller.build_dep_lines(versions, "    ")

      [line] = lines
      assert line == "    {:excoveralls, \"~> 0.18\", only: :test},"
    end

    test "formats doctor with dev only" do
      versions = %{doctor: {:doctor, "~> 0.21"}}
      lines = DepInstaller.build_dep_lines(versions, "    ")

      [line] = lines
      assert line == "    {:doctor, \"~> 0.21\", only: :dev},"
    end

    test "formats mix_audit with dev and test" do
      versions = %{audit: {:mix_audit, "~> 2.1"}}
      lines = DepInstaller.build_dep_lines(versions, "    ")

      [line] = lines
      assert line == "    {:mix_audit, \"~> 2.1\", only: [:dev, :test], runtime: false},"
    end

    test "formats gettext as runtime dependency" do
      versions = %{gettext: {:gettext, "~> 0.24"}}
      lines = DepInstaller.build_dep_lines(versions, "    ")

      [line] = lines
      assert line == "    {:gettext, \"~> 0.24\"},"
    end

    test "formats multiple dependencies with correct options for each" do
      versions = %{
        credo: {:credo, "~> 1.7"},
        dialyzer: {:dialyxir, "~> 1.4"},
        coverage: {:excoveralls, "~> 0.18"}
      }

      lines = DepInstaller.build_dep_lines(versions, "  ")

      assert length(lines) == 3
      assert Enum.all?(lines, &String.starts_with?(&1, "  {:"))
      assert Enum.all?(lines, &String.ends_with?(&1, "},"))

      # Verify each tool has its specific options
      credo_line = Enum.find(lines, &String.contains?(&1, ":credo"))
      assert credo_line =~ "only: [:dev, :test], runtime: false"

      dialyzer_line = Enum.find(lines, &String.contains?(&1, ":dialyxir"))
      assert dialyzer_line =~ "only: [:dev], runtime: false"

      coverage_line = Enum.find(lines, &String.contains?(&1, ":excoveralls"))
      assert coverage_line =~ "only: :test"
      refute coverage_line =~ "runtime"
    end

    test "uses provided indentation" do
      versions = %{credo: {:credo, "~> 1.7"}}
      lines = DepInstaller.build_dep_lines(versions, "\t\t")

      [line] = lines
      assert String.starts_with?(line, "\t\t{:")
    end
  end

  describe "insert_lines/3" do
    test "inserts lines at correct position" do
      content = "line1\nline2\nline3"
      new_lines = ["new1", "new2"]

      result = DepInstaller.insert_lines(content, 2, new_lines)

      assert result == "line1\nline2\nnew1\nnew2\nline3"
    end

    test "inserts at beginning" do
      content = "line1\nline2"
      new_lines = ["new"]

      result = DepInstaller.insert_lines(content, 0, new_lines)

      assert result == "new\nline1\nline2"
    end

    test "inserts at end" do
      content = "line1\nline2"
      new_lines = ["new"]

      result = DepInstaller.insert_lines(content, 2, new_lines)

      assert result == "line1\nline2\nnew"
    end

    test "handles empty new_lines" do
      content = "line1\nline2"

      result = DepInstaller.insert_lines(content, 1, [])

      assert result == content
    end
  end

  describe "add_dependencies/1" do
    @tag :tmp_dir
    test "adds dependencies to mix.exs", %{tmp_dir: dir} do
      File.cd!(dir, fn ->
        # Create minimal mix.exs
        original_content = ~S"""
defmodule TestProject.MixProject do
  use Mix.Project

  def project do
    [app: :test_project]
  end

  defp deps do
    [
      {:ex_quality, "~> 0.1", only: :dev, runtime: false}
    ]
  end
end
"""

        File.write!("mix.exs", original_content)

        versions = %{
          credo: {:credo, "~> 1.7"},
          dialyzer: {:dialyxir, "~> 1.4"}
        }

        assert :ok = DepInstaller.add_dependencies(versions)

        # Verify file was modified
        modified = File.read!("mix.exs")
        assert modified =~ "{:credo, \"~> 1.7\", only: [:dev, :test], runtime: false}"
        # Dialyzer should be dev only
        assert modified =~ "{:dialyxir, \"~> 1.4\", only: [:dev], runtime: false}"

        # Verify backup was created
        assert File.exists?("mix.exs.backup")
        backup = File.read!("mix.exs.backup")
        assert backup == original_content

        # Verify syntax is valid
        assert {:ok, _ast} = Code.string_to_quoted(modified)
      end)
    end

    @tag :tmp_dir
    test "handles empty versions map", %{tmp_dir: dir} do
      File.cd!(dir, fn ->
        File.write!("mix.exs", "defmodule Test do\nend")

        assert :ok = DepInstaller.add_dependencies(%{})

        # Should not modify file
        refute File.exists?("mix.exs.backup")
      end)
    end

    @tag :tmp_dir
    test "returns error if mix.exs not found", %{tmp_dir: dir} do
      File.cd!(dir, fn ->
        # Run in a temporary directory without mix.exs
        result = DepInstaller.add_dependencies(%{credo: {:credo, "~> 1.7"}})

        assert {:error, message} = result
        assert message =~ "mix.exs not found"
      end)
    end
  end
end
