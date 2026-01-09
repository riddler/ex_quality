defmodule Quality.Stages.FormatTest do
  use ExUnit.Case, async: false

  @moduletag :integration

  alias Quality.Stages.Format

  describe "run/1" do
    test "returns a success result map with required fields" do
      result = Format.run([])

      assert is_map(result)
      assert result.name == "Format"
      assert result.status == :ok
      assert is_binary(result.output)
      assert is_map(result.stats)
      assert is_binary(result.summary)
      assert is_integer(result.duration_ms)
      assert result.duration_ms >= 0
    end

    test "includes files_formatted in stats" do
      result = Format.run([])

      assert Map.has_key?(result.stats, :files_formatted)
      assert is_integer(result.stats.files_formatted)
      assert result.stats.files_formatted >= 0
    end

    test "summary reflects number of files formatted" do
      result = Format.run([])

      case result.stats.files_formatted do
        0 ->
          assert result.summary == "No changes needed"

        1 ->
          assert result.summary == "Formatted 1 file"

        n when n > 1 ->
          assert result.summary == "Formatted #{n} files"
      end
    end

    test "output contains list of formatted files when files are changed" do
      result = Format.run([])

      # If files were formatted, output should list them
      if result.stats.files_formatted > 0 do
        assert result.output != ""
        # Output should contain file paths
        assert result.output =~ ~r/\.exs?/
      else
        # If no files were formatted, output should be empty
        assert result.output == ""
      end
    end

    test "always returns :ok status" do
      # Format stage never fails
      result = Format.run([])

      assert result.status == :ok
    end

    test "output lists one file per line when multiple files formatted" do
      result = Format.run([])

      if result.stats.files_formatted > 1 do
        lines =
          result.output
          |> String.split("\n")
          |> Enum.reject(&(&1 == ""))

        # Should have one line per formatted file
        assert length(lines) == result.stats.files_formatted

        # Each line should be a file path
        Enum.each(lines, fn line ->
          assert line =~ ~r/\.exs?$/
        end)
      end
    end

    test "ignores config parameter" do
      # Config is not used by format stage
      result1 = Format.run([])
      result2 = Format.run(some_option: true)

      # Both should work and have similar structure
      assert result1.name == result2.name
      assert result1.status == result2.status
    end
  end

  describe "file parsing" do
    # These tests verify the behavior indirectly through run/1
    # since parse_files_needing_format is private

    test "only includes .ex and .exs files in output" do
      result = Format.run([])

      if result.output != "" do
        lines = String.split(result.output, "\n", trim: true)

        Enum.each(lines, fn line ->
          assert String.ends_with?(line, ".ex") or String.ends_with?(line, ".exs")
        end)
      end
    end

    test "empty output when no files need formatting" do
      # Run format once to ensure everything is formatted
      Format.run([])

      # Run again - should report no changes
      result = Format.run([])

      assert result.stats.files_formatted == 0
      assert result.output == ""
      assert result.summary == "No changes needed"
    end
  end

  describe "timing" do
    test "records execution duration" do
      result = Format.run([])

      # Duration should be reasonable (less than 10 seconds for most projects)
      assert result.duration_ms >= 0
      assert result.duration_ms < 10_000
    end

    test "duration increases with work done" do
      # This is a basic sanity check that timing works
      result = Format.run([])

      # If any files were formatted, duration should be > 0
      if result.stats.files_formatted > 0 do
        assert result.duration_ms > 0
      end
    end
  end
end
