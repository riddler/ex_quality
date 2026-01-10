defmodule ExQuality.Init.VersionResolverTest do
  use ExUnit.Case, async: true

  alias ExQuality.Init.VersionResolver

  describe "parse_version_from_output/1" do
    test "parses version from Config line" do
      output = """
      A static code analysis tool

      Config: {:credo, "~> 1.7"}
      Locked version: 1.7.15
      Releases: 1.7.15, 1.7.14, 1.7.13
      """

      assert VersionResolver.parse_version_from_output(output) == "~> 1.7"
    end

    test "parses version from Config line without colon before package name" do
      output = """
      Mix tasks to simplify use of Dialyzer

      Config: {dialyxir, "~> 1.4"}
      Locked version: 1.4.7
      """

      assert VersionResolver.parse_version_from_output(output) == "~> 1.4"
    end

    test "falls back to Releases line if Config missing" do
      output = """
      Code coverage tool

      Releases: 0.18.2, 0.18.1, 0.18.0, 0.17.0
      """

      assert VersionResolver.parse_version_from_output(output) == "~> 0.18"
    end

    test "uses fallback version if parsing fails" do
      output = "Invalid output with no version information"

      # Should not raise, but use fallback
      assert VersionResolver.parse_version_from_output(output) == "~> 0.1"
    end

    test "handles empty output" do
      output = ""

      assert VersionResolver.parse_version_from_output(output) == "~> 0.1"
    end

    test "parses version with patch number" do
      output = """
      Config: {:excoveralls, "~> 0.18.2"}
      """

      assert VersionResolver.parse_version_from_output(output) == "~> 0.18.2"
    end

    test "parses version with = operator" do
      output = """
      Config: {:some_package, "== 2.0.0"}
      """

      assert VersionResolver.parse_version_from_output(output) == "== 2.0.0"
    end
  end

  describe "fetch_versions/1" do
    test "returns map of tool to package and version tuples" do
      # This is a live test that requires network access
      # We'll test with a single common package
      result = VersionResolver.fetch_versions([:credo])

      assert is_map(result)
      assert {:credo, version} = result[:credo]
      # Version should be a string starting with ~>
      assert is_binary(version)
      assert String.starts_with?(version, "~>") or String.starts_with?(version, "==")
    end

    test "handles multiple tools" do
      result = VersionResolver.fetch_versions([:credo, :dialyzer])

      assert map_size(result) == 2
      assert {:credo, _} = result[:credo]
      assert {:dialyxir, _} = result[:dialyzer]
    end

    test "maps tool names to correct package names" do
      result = VersionResolver.fetch_versions([:dialyzer, :coverage, :audit])

      # dialyzer maps to :dialyxir
      assert {:dialyxir, _} = result[:dialyzer]
      # coverage maps to :excoveralls
      assert {:excoveralls, _} = result[:coverage]
      # audit maps to :mix_audit
      assert {:mix_audit, _} = result[:audit]
    end
  end
end
