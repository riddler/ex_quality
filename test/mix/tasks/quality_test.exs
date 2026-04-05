defmodule Mix.Tasks.QualityTest do
  use ExUnit.Case, async: false
  use Mimic

  import ExUnit.CaptureIO

  describe "failure output is not truncated" do
    test "displays complete failure output for large outputs" do
      # Generate a large output string (1000 lines of realistic error output)
      line_count = 1000

      large_output =
        Enum.map_join(1..line_count, "\n", fn i ->
          padded = String.pad_leading(Integer.to_string(i), 4, "0")
          "  #{padded}) test some_module test_#{i} (MyApp.SomeTest)"
        end)

      test_output = large_output <> "\n\n#{line_count} tests, #{line_count} failures\n"

      ExQuality.Tools
      |> stub(:detect, fn ->
        %{credo: false, dialyzer: false, doctor: false, gettext: false, coverage: false, audit: false}
      end)
      |> stub(:available?, fn _tool -> false end)

      System
      |> stub(:cmd, fn
        "mix", ["format", "--check-formatted"], _opts ->
          {"", 0}

        "mix", ["format"], _opts ->
          {"", 0}

        "mix", ["compile" | _], _opts ->
          {"", 0}

        "mix", ["test" | _], _opts ->
          {test_output, 1}

        _cmd, _args, _opts ->
          {"", 0}
      end)

      captured =
        capture_io(fn ->
          try do
            Mix.Tasks.Quality.run([])
          rescue
            Mix.Error -> :ok
          end
        end)

      # Verify every line of the large output appears in captured output
      for i <- [1, 100, 500, 750, 999, line_count] do
        padded = String.pad_leading(Integer.to_string(i), 4, "0")
        assert captured =~ "#{padded}) test some_module test_#{i}",
               "Line #{i} of #{line_count} was truncated from the failure output"
      end

      # Verify the output is contiguous by checking total line presence
      output_lines = String.split(large_output, "\n")

      missing_lines =
        output_lines
        |> Enum.with_index(1)
        |> Enum.reject(fn {line, _idx} -> String.contains?(captured, String.trim(line)) end)

      assert missing_lines == [],
             "#{length(missing_lines)} of #{line_count} output lines were truncated"
    end

    test "writes failure output directly to stdout, not through Mix.shell" do
      # This test verifies the fix: failure output must go through IO.write
      # (which writes to stdout) rather than Mix.shell().info (which routes
      # through the configured shell and can truncate large output).
      #
      # When Mix.shell is set to Mix.Shell.Process, Mix.shell().info sends
      # messages to the process mailbox instead of stdout. IO.write always
      # goes to stdout. So if failure output appears in capture_io, it
      # proves IO.write is being used.

      failure_output = "UNIQUE_FAILURE_MARKER: the test suite failed spectacularly\n"

      ExQuality.Tools
      |> stub(:detect, fn ->
        %{credo: false, dialyzer: false, doctor: false, gettext: false, coverage: false, audit: false}
      end)
      |> stub(:available?, fn _tool -> false end)

      System
      |> stub(:cmd, fn
        "mix", ["format", "--check-formatted"], _opts ->
          {"", 0}

        "mix", ["format"], _opts ->
          {"", 0}

        "mix", ["compile" | _], _opts ->
          {"", 0}

        "mix", ["test" | _], _opts ->
          {failure_output <> "1 tests, 1 failures\n", 1}

        _cmd, _args, _opts ->
          {"", 0}
      end)

      # Use Mix.Shell.Process so that Mix.shell().info sends messages
      # to the process mailbox instead of stdout
      original_shell = Mix.shell()
      Mix.shell(Mix.Shell.Process)

      captured =
        capture_io(fn ->
          try do
            Mix.Tasks.Quality.run([])
          rescue
            Mix.Error -> :ok
          end
        end)

      Mix.shell(original_shell)

      # The failure output should appear in captured IO (written via IO.write
      # to stdout) rather than only in process messages (Mix.shell().info).
      # With the old code (Mix.shell().info), this line would NOT appear in
      # capture_io when using Mix.Shell.Process.
      assert captured =~ "UNIQUE_FAILURE_MARKER",
             "Failure output was not written to stdout. " <>
               "It was likely routed through Mix.shell().info instead of IO.write, " <>
               "which can cause truncation in certain environments."
    end
  end
end
