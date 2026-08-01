defmodule Mix.Tasks.QualityTest do
  use ExUnit.Case, async: false
  use Mimic

  import ExUnit.CaptureIO

  alias Mix.Tasks.Quality

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
        %{
          credo: false,
          dialyzer: false,
          doctor: false,
          gettext: false,
          coverage: false,
          audit: false,
          sobelow: false
        }
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
            Quality.run([])
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
        %{
          credo: false,
          dialyzer: false,
          doctor: false,
          gettext: false,
          coverage: false,
          audit: false,
          sobelow: false
        }
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
            Quality.run([])
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

  describe "stages that do not run say so" do
    test "reports a reason for every stage that was considered and skipped" do
      # No tools installed, so every optional stage is skipped for a
      # different-looking reason than "it passed".
      ExQuality.Tools
      |> stub(:detect, fn ->
        %{
          credo: false,
          dialyzer: false,
          doctor: false,
          gettext: false,
          coverage: false,
          audit: false,
          sobelow: false
        }
      end)
      |> stub(:available?, fn _tool -> false end)

      System
      |> stub(:cmd, fn
        "mix", ["test" | _], _opts -> {"1 tests, 0 failures\n", 0}
        _cmd, _args, _opts -> {"", 0}
      end)

      captured = capture_io(fn -> Quality.run([]) end)

      assert captured =~ "○ Credo: skipped (:credo not installed)"
      assert captured =~ "○ Dialyzer: skipped (:dialyxir not installed)"
      assert captured =~ "○ Doctor: skipped (:doctor not installed)"
      assert captured =~ "○ Gettext: skipped (:gettext not installed)"

      # Dependencies has no tool of its own, so it still runs.
      refute captured =~ "○ Dependencies"
      assert captured =~ "All quality checks passed"
    end

    test "attributes a skip to the CLI switch that caused it" do
      ExQuality.Tools
      |> stub(:detect, fn ->
        %{
          credo: true,
          dialyzer: true,
          doctor: false,
          gettext: false,
          coverage: false,
          audit: false,
          sobelow: false
        }
      end)
      |> stub(:available?, fn tool -> tool in [:credo, :dialyzer] end)

      System
      |> stub(:cmd, fn
        "mix", ["test" | _], _opts -> {"1 tests, 0 failures\n", 0}
        _cmd, _args, _opts -> {"", 0}
      end)

      captured = capture_io(fn -> Quality.run(["--skip-credo"]) end)

      assert captured =~ "○ Credo: skipped (--skip-credo)"
      refute captured =~ "✓ Credo"
    end

    test "attributes a dialyzer skip to quick mode" do
      ExQuality.Tools
      |> stub(:detect, fn ->
        %{
          credo: false,
          dialyzer: true,
          doctor: false,
          gettext: false,
          coverage: false,
          audit: false,
          sobelow: false
        }
      end)
      |> stub(:available?, fn tool -> tool == :dialyzer end)

      System
      |> stub(:cmd, fn
        "mix", ["test" | _], _opts -> {"1 tests, 0 failures\n", 0}
        _cmd, _args, _opts -> {"", 0}
      end)

      captured = capture_io(fn -> Quality.run(["--quick"]) end)

      assert captured =~ "○ Dialyzer: skipped (--quick)"
      refute captured =~ "✓ Dialyzer"
    end
  end

  describe "failure output uses findings when a stage supplies them" do
    test "renders credo issues grouped by file instead of raw tool output" do
      issues = [
        %{
          check: "Credo.Check.Warning.MissingDoc",
          category: "warning",
          filename: "lib/my_app/user.ex",
          line_no: 15,
          column: 11,
          message: "Modules should have a @moduledoc tag."
        },
        %{
          check: "Credo.Check.Refactor.Nesting",
          category: "refactor",
          filename: "lib/my_app/api.ex",
          line_no: 42,
          column: 3,
          message: "Function body is nested too deep."
        }
      ]

      credo_output =
        "Checking 24 source files ...\n" <> Jason.encode!(%{issues: issues}, pretty: true)

      ExQuality.Tools
      |> stub(:detect, fn ->
        %{
          credo: true,
          dialyzer: false,
          doctor: false,
          gettext: false,
          coverage: false,
          audit: false,
          sobelow: false
        }
      end)
      |> stub(:available?, fn tool -> tool == :credo end)

      System
      |> stub(:cmd, fn
        "mix", ["credo" | _], _opts -> {credo_output, 1}
        _cmd, _args, _opts -> {"", 0}
      end)

      captured =
        capture_io(fn ->
          try do
            Quality.run([])
          rescue
            Mix.Error -> :ok
          end
        end)

      assert captured =~ "lib/my_app/api.ex\n  42:3  [info] Function body is nested too deep."
      assert captured =~ "lib/my_app/user.ex\n  15:11  [warning] Modules should have a @moduledoc"

      # The banner and summary chatter around the issues is not the finding,
      # so it should not be reprinted alongside them.
      refute captured =~ "Checking 24 source files"
    end
  end

  describe "machine-readable output" do
    setup do
      issue = %{
        check: "Credo.Check.Warning.MissingDoc",
        category: "warning",
        filename: "lib/my_app/user.ex",
        line_no: 15,
        column: 11,
        message: "Modules should have a @moduledoc tag."
      }

      credo_output = Jason.encode!(%{issues: [issue]}, pretty: true)

      ExQuality.Tools
      |> stub(:detect, fn ->
        %{
          credo: true,
          dialyzer: false,
          doctor: false,
          gettext: false,
          coverage: false,
          audit: false,
          sobelow: false
        }
      end)
      |> stub(:available?, fn tool -> tool == :credo end)

      System
      |> stub(:cmd, fn
        "mix", ["credo" | _], _opts -> {credo_output, 1}
        "mix", ["test" | _], _opts -> {"1 tests, 0 failures\n", 0}
        _cmd, _args, _opts -> {"", 0}
      end)

      :ok
    end

    test "--report writes a report to a file and leaves stdout human" do
      path = Path.join(System.tmp_dir!(), "quality-#{System.unique_integer([:positive])}.json")
      on_exit(fn -> File.rm(path) end)

      captured = capture_io(fn -> run_failing(["--report", path]) end)

      assert captured =~ "Modules should have a @moduledoc tag."
      refute captured =~ ~s("version")

      report = path |> File.read!() |> Jason.decode!()

      assert report["status"] == "error"
      assert report["version"] == to_string(Application.spec(:ex_quality, :vsn))
      assert is_integer(report["duration_ms"])

      credo = Enum.find(report["stages"], &(&1["name"] == "Credo"))

      assert credo["status"] == "error"

      assert [%{"file" => "lib/my_app/user.ex", "line" => 15, "column" => 11}] =
               credo["findings"]
    end

    test "--format json puts the report on stdout and the human stream on stderr" do
      captured = capture_io(fn -> run_failing(["--format", "json"]) end)

      report = Jason.decode!(captured)

      assert report["status"] == "error"

      # Every stage the run considered is present, skipped ones included, so a
      # caller never has to read absence as success.
      assert Enum.map(report["stages"], & &1["name"]) == [
               "Format",
               "Compile",
               "Dialyzer",
               "Doctor",
               "Gettext",
               "Sobelow",
               "Credo",
               "Dependencies",
               "Tests"
             ]
    end

    test "--format json still writes the human stream, to stderr" do
      stderr =
        capture_io(:stderr, fn ->
          capture_io(fn -> run_failing(["--format", "json"]) end)
        end)

      assert stderr =~ "Running quality checks"
      assert stderr =~ "Credo - FAILED"
      assert stderr =~ "Modules should have a @moduledoc tag."
    end

    test "restores the shell after the run" do
      shell = Mix.shell()

      capture_io(fn -> run_failing(["--format", "json"]) end)

      assert Mix.shell() == shell
    end

    test "rejects a format it does not know" do
      assert_raise Mix.Error, ~r/Unknown --format/, fn ->
        capture_io(fn -> Quality.run(["--format", "xml"]) end)
      end
    end

    test "a report is written even when no stage fails" do
      path = Path.join(System.tmp_dir!(), "quality-#{System.unique_integer([:positive])}.json")
      on_exit(fn -> File.rm(path) end)

      capture_io(fn -> run_failing(["--report", path, "--skip-credo"]) end)

      report = path |> File.read!() |> Jason.decode!()

      assert report["status"] == "ok"

      credo = Enum.find(report["stages"], &(&1["name"] == "Credo"))

      assert credo["status"] == "skipped"
      assert credo["summary"] == "--skip-credo"
    end

    test "a run that stops at compile still accounts for every later stage" do
      path = Path.join(System.tmp_dir!(), "quality-#{System.unique_integer([:positive])}.json")
      on_exit(fn -> File.rm(path) end)

      System
      |> stub(:cmd, fn
        "mix", ["compile" | _], _opts -> {"** (CompileError) lib/a.ex:1: boom\n", 1}
        _cmd, _args, _opts -> {"", 0}
      end)

      captured = capture_io(fn -> run_failing(["--report", path]) end)

      # The analysis stages never ran, and silence about them would read as a
      # clean bill of health for code that was never checked.
      assert captured =~ "○ Credo: skipped (compile failed)"
      assert captured =~ "○ Tests: skipped (compile failed)"

      report = path |> File.read!() |> Jason.decode!()

      assert report["status"] == "error"

      statuses = Map.new(report["stages"], &{&1["name"], &1["status"]})

      assert statuses["Compile (dev)"] == "error"
      assert statuses["Credo"] == "skipped"
      assert statuses["Tests"] == "skipped"

      compile = Enum.find(report["stages"], &(&1["name"] == "Compile (dev)"))

      assert compile["output"] =~ "boom"
    end
  end

  # The runs above fail on purpose; the report is the thing under test, not
  # the exception Mix raises afterwards.
  defp run_failing(args) do
    Quality.run(args)
  rescue
    Mix.Error -> :ok
  end
end
