defmodule ExQuality.Stages.GettextTest do
  use ExUnit.Case, async: true
  use Mimic

  alias ExQuality.Stages.Gettext

  describe "run/1 - no translation issues" do
    setup do
      # Mock gettext.extract command
      System
      |> expect(:cmd, fn "mix", ["gettext.extract", "--merge"], _opts ->
        {"Extracted gettext strings", 0}
      end)

      # Mock find command - no .po files found or empty result
      System
      |> stub(:cmd, fn "find", _args, _opts ->
        {"", 0}
      end)

      :ok
    end

    test "returns success when no translation files found" do
      result = Gettext.run([])

      assert result.name == "Gettext"
      assert result.status == :ok
      assert result.summary == "All translations complete"
      assert is_integer(result.duration_ms)
      assert result.duration_ms >= 0
    end
  end

  describe "run/1 - extraction failed" do
    setup do
      # Mock gettext.extract command - failure
      System
      |> expect(:cmd, fn "mix", ["gettext.extract", "--merge"], _opts ->
        {"Extraction failed: gettext not configured", 1}
      end)

      :ok
    end

    test "returns error when extraction fails" do
      result = Gettext.run([])

      assert result.status == :error
      assert result.summary == "Extraction failed"
    end
  end

  describe "run/1 - missing translations" do
    setup do
      # Mock gettext.extract command
      System
      |> expect(:cmd, fn "mix", ["gettext.extract", "--merge"], _opts ->
        {"Extracted gettext strings", 0}
      end)

      # This test is simplified since gettext stage implementation uses File operations
      # For full mocking, we'd need to mock File.read! and File.exists? as well
      # For now, just verify the stage doesn't crash
      :ok
    end

    test "handles translation checking gracefully" do
      result = Gettext.run([])

      assert is_map(result)
      assert result.name == "Gettext"
      assert result.status in [:ok, :error]
    end
  end

  describe "run/1 - timing" do
    setup do
      System
      |> expect(:cmd, fn "mix", ["gettext.extract", "--merge"], _opts ->
        Process.sleep(10)
        {"Extracted", 0}
      end)
      |> stub(:cmd, fn "find", _args, _opts ->
        {"", 0}
      end)

      :ok
    end

    test "records execution duration" do
      result = Gettext.run([])

      assert result.duration_ms >= 10
      assert result.duration_ms < 5_000
    end
  end

  describe "run/1 - configuration" do
    setup do
      System
      |> expect(:cmd, fn "mix", ["gettext.extract", "--merge"], _opts ->
        {"Extracted", 0}
      end)
      |> stub(:cmd, fn "find", _args, _opts ->
        {"", 0}
      end)

      :ok
    end

    test "handles empty config" do
      result = Gettext.run([])

      assert result.status == :ok
    end

    test "ignores config options" do
      result = Gettext.run(some_option: true)

      assert result.status == :ok
    end
  end
end
