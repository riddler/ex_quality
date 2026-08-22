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

  describe "run/1 - mix format fails" do
    setup do
      format_output = """
      ** (SyntaxError) lib/my_app/user.ex:12:1: unexpected reserved word: end
          (elixir 1.17.0) lib/code.ex:1234: Code.string_to_quoted!/2
      """

      System
      |> expect(:cmd, fn "mix", ["format", "--check-formatted"], _opts ->
        {format_output, 1}
      end)
      |> expect(:cmd, fn "mix", ["format"], _opts ->
        {format_output, 1}
      end)

      :ok
    end

    test "reports the failure instead of a green tick" do
      result = Format.run([])

      assert result.status == :error
      assert result.summary == "mix format failed"
    end

    test "keeps the tool's output, which names the broken file" do
      result = Format.run([])

      assert result.output =~ "SyntaxError"
      assert result.output =~ "lib/my_app/user.ex:12:1"
    end
  end

  # In check mode the only System.cmd expectation set is the check itself, so
  # a `mix format` write would fail the test as an unexpected call: the
  # no-write property is asserted by construction, not just by status.
  describe "run/1 - check mode, clean tree" do
    setup do
      System
      |> expect(:cmd, fn "mix", ["format", "--check-formatted"], _opts ->
        {"", 0}
      end)

      :ok
    end

    test "passes without writing" do
      result = Format.run(format: [check: true])

      assert result.name == "Format"
      assert result.status == :ok
      assert result.output == ""
      assert result.stats.files_needing_format == 0
      assert result.summary == "No changes needed"
    end
  end

  describe "run/1 - check mode, drift" do
    setup do
      check_output = """
      lib/my_app/user.ex
      test/my_app_test.exs
      ** (Mix) mix format failed due to --check-formatted
      """

      System
      |> expect(:cmd, fn "mix", ["format", "--check-formatted"], _opts ->
        {check_output, 1}
      end)

      :ok
    end

    test "fails with the file list, leaving the tree untouched" do
      result = Format.run(format: [check: true])

      assert result.status == :error
      assert result.summary == "2 files need formatting"
      assert result.stats.files_needing_format == 2

      lines = String.split(result.output, "\n", trim: true)
      assert "lib/my_app/user.ex" in lines
      assert "test/my_app_test.exs" in lines
    end
  end

  describe "run/1 - check mode, one drifting file" do
    test "a single file is a singular summary" do
      System
      |> expect(:cmd, fn "mix", ["format", "--check-formatted"], _opts ->
        {"lib/my_app/user.ex\n", 1}
      end)

      result = Format.run(format: [check: true])

      assert result.summary == "1 file needs formatting"
      assert result.stats.files_needing_format == 1
    end
  end

  describe "run/1 - check mode, mix format itself fails" do
    setup do
      # A syntax error names no .ex file as a bare line, so there is no drift
      # list to report - only the tool's own account of what broke.
      check_output = """
      ** (SyntaxError) invalid syntax found on lib/my_app/user.ex:12:1:
          (elixir 1.17.0) lib/code.ex:1234: Code.string_to_quoted!/2
      """

      System
      |> expect(:cmd, fn "mix", ["format", "--check-formatted"], _opts ->
        {check_output, 1}
      end)

      :ok
    end

    test "reports the failure with the tool's output, same as write mode" do
      result = Format.run(format: [check: true])

      assert result.status == :error
      assert result.summary == "mix format failed"
      assert result.output =~ "SyntaxError"
      assert result.output =~ "lib/my_app/user.ex:12:1"
    end
  end

  describe "run/1 - check mode is off by default" do
    test "an absent option behaves exactly as before" do
      System
      |> expect(:cmd, fn "mix", ["format", "--check-formatted"], _opts ->
        {"lib/my_app/user.ex\n", 1}
      end)
      |> expect(:cmd, fn "mix", ["format"], _opts ->
        {"", 0}
      end)

      result = Format.run(format: [])

      assert result.status == :ok
      assert result.summary == "Formatted 1 file"
      assert result.stats.files_formatted == 1
    end

    test "check: false behaves exactly as before" do
      System
      |> expect(:cmd, fn "mix", ["format", "--check-formatted"], _opts ->
        {"", 0}
      end)
      |> expect(:cmd, fn "mix", ["format"], _opts ->
        {"", 0}
      end)

      result = Format.run(format: [check: false])

      assert result.status == :ok
      assert result.stats.files_formatted == 0
    end
  end

  describe "run/1 - valid code" do
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

    test "passes, since format cannot fail on code it can parse" do
      result = Format.run([])

      assert result.status == :ok
    end
  end
end
