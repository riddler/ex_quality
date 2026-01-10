defmodule ExQuality.Stages.FormatTest do
  use ExUnit.Case, async: true
  use Mimic

  alias ExQuality.Stages.Format

  describe "run/1 - no files need formatting" do
    setup do
      # Mock: mix format --check-formatted returns 0 (all files formatted)
      System
      |> expect(:cmd, fn "mix", ["format", "--check-formatted"], _opts ->
        {"", 0}
      end)
      # Mock: mix format (actual formatting)
      |> expect(:cmd, fn "mix", ["format"], _opts ->
        {"", 0}
      end)

      :ok
    end

    test "returns success with no changes needed" do
      result = Format.run([])

      assert result.name == "Format"
      assert result.status == :ok
      assert result.output == ""
      assert result.stats.files_formatted == 0
      assert result.summary == "No changes needed"
      assert is_integer(result.duration_ms)
      assert result.duration_ms >= 0
    end
  end

  describe "run/1 - one file needs formatting" do
    setup do
      check_output = """
      lib/my_app/user.ex
      ** (Mix) mix format failed due to --check-formatted
      """

      # Mock: mix format --check-formatted returns non-zero with file list
      System
      |> expect(:cmd, fn "mix", ["format", "--check-formatted"], _opts ->
        {check_output, 1}
      end)
      # Mock: mix format (actual formatting)
      |> expect(:cmd, fn "mix", ["format"], _opts ->
        {"", 0}
      end)

      :ok
    end

    test "returns success with one file formatted" do
      result = Format.run([])

      assert result.name == "Format"
      assert result.status == :ok
      assert result.output == "lib/my_app/user.ex"
      assert result.stats.files_formatted == 1
      assert result.summary == "Formatted 1 file"
    end
  end

  describe "run/1 - multiple files need formatting" do
    setup do
      check_output = """
      lib/my_app/user.ex
      lib/my_app/api.ex
      test/my_app_test.exs
      ** (Mix) mix format failed due to --check-formatted
      """

      # Mock: mix format --check-formatted returns non-zero with file list
      System
      |> expect(:cmd, fn "mix", ["format", "--check-formatted"], _opts ->
        {check_output, 1}
      end)
      # Mock: mix format (actual formatting)
      |> expect(:cmd, fn "mix", ["format"], _opts ->
        {"", 0}
      end)

      :ok
    end

    test "returns success with multiple files formatted" do
      result = Format.run([])

      assert result.name == "Format"
      assert result.status == :ok
      assert result.stats.files_formatted == 3
      assert result.summary == "Formatted 3 files"

      # Output should list all files, one per line
      lines = String.split(result.output, "\n", trim: true)
      assert length(lines) == 3
      assert "lib/my_app/user.ex" in lines
      assert "lib/my_app/api.ex" in lines
      assert "test/my_app_test.exs" in lines
    end

    test "output lists one file per line" do
      result = Format.run([])

      lines = String.split(result.output, "\n", trim: true)
      assert length(lines) == result.stats.files_formatted

      # Each line should be a file path
      Enum.each(lines, fn line ->
        assert line =~ ~r/\.exs?$/
      end)
    end
  end

  describe "run/1 - filters out non-elixir files" do
    setup do
      check_output = """
      Some error message
      lib/my_app/user.ex
      README.md
      config/config.exs
      package.json
      ** (Mix) mix format failed
      """

      # Mock: mix format --check-formatted returns non-zero with mixed output
      System
      |> expect(:cmd, fn "mix", ["format", "--check-formatted"], _opts ->
        {check_output, 1}
      end)
      # Mock: mix format (actual formatting)
      |> expect(:cmd, fn "mix", ["format"], _opts ->
        {"", 0}
      end)

      :ok
    end

    test "only includes .ex and .exs files" do
      result = Format.run([])

      assert result.stats.files_formatted == 2
      assert result.summary == "Formatted 2 files"

      lines = String.split(result.output, "\n", trim: true)
      assert length(lines) == 2
      assert "lib/my_app/user.ex" in lines
      assert "config/config.exs" in lines

      # Should not include non-Elixir files
      refute result.output =~ "README.md"
      refute result.output =~ "package.json"
    end
  end

  describe "run/1 - handles empty lines and whitespace" do
    setup do
      check_output = """

      lib/my_app/user.ex

      lib/my_app/api.ex

      ** (Mix) mix format failed
      """

      # Mock: mix format --check-formatted returns non-zero with empty lines
      System
      |> expect(:cmd, fn "mix", ["format", "--check-formatted"], _opts ->
        {check_output, 1}
      end)
      # Mock: mix format (actual formatting)
      |> expect(:cmd, fn "mix", ["format"], _opts ->
        {"", 0}
      end)

      :ok
    end

    test "filters out empty lines" do
      result = Format.run([])

      assert result.stats.files_formatted == 2
      lines = String.split(result.output, "\n", trim: true)
      assert length(lines) == 2
    end
  end

  describe "run/1 - ignores config parameter" do
    test "works with empty config" do
      System
      |> expect(:cmd, fn "mix", ["format", "--check-formatted"], _opts ->
        {"", 0}
      end)
      |> expect(:cmd, fn "mix", ["format"], _opts ->
        {"", 0}
      end)

      result = Format.run([])
      assert result.status == :ok
    end

    test "works with arbitrary config" do
      System
      |> expect(:cmd, fn "mix", ["format", "--check-formatted"], _opts ->
        {"", 0}
      end)
      |> expect(:cmd, fn "mix", ["format"], _opts ->
        {"", 0}
      end)

      result = Format.run(some_option: true, another: false)
      assert result.status == :ok
    end
  end

  describe "run/1 - timing" do
    setup do
      # Mock: mix format --check-formatted returns 0 (all files formatted)
      System
      |> expect(:cmd, fn "mix", ["format", "--check-formatted"], _opts ->
        # Simulate some work
        Process.sleep(10)
        {"", 0}
      end)
      # Mock: mix format (actual formatting)
      |> expect(:cmd, fn "mix", ["format"], _opts ->
        {"", 0}
      end)

      :ok
    end

    test "records execution duration" do
      result = Format.run([])

      # Duration should be at least the sleep time
      assert result.duration_ms >= 10
      # But should be reasonable (not hanging)
      assert result.duration_ms < 5_000
    end
  end

  describe "run/1 - always returns :ok status" do
    setup do
      # Mock: mix format --check-formatted returns 0 (all files formatted)
      System
      |> expect(:cmd, fn "mix", ["format", "--check-formatted"], _opts ->
        {"", 0}
      end)
      # Mock: mix format (actual formatting)
      |> expect(:cmd, fn "mix", ["format"], _opts ->
        {"", 0}
      end)

      :ok
    end

    test "format stage never fails" do
      result = Format.run([])

      # Format always succeeds - it can't fail on valid Elixir code
      assert result.status == :ok
    end
  end
end
