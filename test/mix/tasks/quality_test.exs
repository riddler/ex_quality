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

  describe "stages that write to the build are kept out of the parallel set" do
    setup do
      ExQuality.Tools
      |> stub(:detect, fn ->
        %{
          credo: true,
          dialyzer: true,
          doctor: false,
          gettext: true,
          coverage: false,
          audit: false,
          sobelow: false
        }
      end)
      |> stub(:available?, fn tool -> tool in [:credo, :dialyzer, :gettext] end)

      :ok
    end

    test "the writer finishes before any reader starts" do
      # Gettext's extraction recompiles the project, so a dialyzer reading the
      # same build while it happens sees the beams change underneath it and
      # reports an analysis that never ran.
      ExQuality.Config
      |> stub(:load, fn _opts -> [gettext: [extract: true], sobelow: [enabled: false]] end)

      test_pid = self()

      System
      |> stub(:cmd, fn
        "mix", ["gettext.extract", "--merge"], _opts ->
          send(test_pid, {:cmd, :gettext_started})
          Process.sleep(50)
          send(test_pid, {:cmd, :gettext_finished})
          {"", 0}

        "mix", ["dialyzer" | _], opts ->
          send(test_pid, {:cmd, :dialyzer_started})
          _collected = Enum.into(["Total errors: 0"], opts[:into])
          {opts[:into], 0}

        "mix", ["credo" | _], _opts ->
          send(test_pid, {:cmd, :credo_started})
          {"", 0}

        "mix", ["test" | _], _opts ->
          send(test_pid, {:cmd, :test_started})
          {"1 tests, 0 failures\n", 0}

        _cmd, _args, _opts ->
          {"", 0}
      end)

      capture_io(fn -> Quality.run([]) end)

      events = drain_events()

      assert :dialyzer_started in events
      assert :credo_started in events

      # Nothing else had started by the time the writer was done.
      assert Enum.take_while(events, &(&1 != :gettext_finished)) == [:gettext_started]
    end

    test "a gettext that only reads stays in the parallel set" do
      ExQuality.Config
      |> stub(:load, fn _opts -> [sobelow: [enabled: false]] end)

      test_pid = self()

      System
      |> stub(:cmd, fn
        "mix", ["gettext.extract" | _], _opts ->
          send(test_pid, {:cmd, :extracted})
          {"", 0}

        "mix", ["dialyzer" | _], opts ->
          _collected = Enum.into(["Total errors: 0"], opts[:into])
          {opts[:into], 0}

        "mix", ["test" | _], _opts ->
          {"1 tests, 0 failures\n", 0}

        _cmd, _args, _opts ->
          {"", 0}
      end)

      capture_io(fn -> Quality.run([]) end)

      refute_received {:cmd, :extracted}
    end

    # The stage events in the order they happened.
    defp drain_events(acc \\ []) do
      receive do
        {:cmd, event} -> drain_events([event | acc])
      after
        0 -> Enum.reverse(acc)
      end
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

    test "the report says which kind of skip each skipped stage is" do
      path = Path.join(System.tmp_dir!(), "quality-#{System.unique_integer([:positive])}.json")
      on_exit(fn -> File.rm(path) end)

      capture_io(fn -> run_failing(["--report", path, "--skip-credo"]) end)

      report = path |> File.read!() |> Jason.decode!()
      kinds = Map.new(report["stages"], &{&1["name"], &1["skip_kind"]})

      # The switch narrows this run; the missing tool is the project's gap;
      # a stage that ran carries null.
      assert kinds["Credo"] == "run"
      assert kinds["Dialyzer"] == "project"
      assert kinds["Format"] == nil
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

  describe "custom stages" do
    defmodule HouseRules do
      @moduledoc false
      def run(_config) do
        %{
          name: "House rules",
          status: :ok,
          output: "",
          stats: %{},
          summary: "Nothing to say",
          duration_ms: 1
        }
      end
    end

    # Only the custom stages and the tests are of interest here, so every
    # built-in analysis stage is off unless a test turns one back on.
    @quiet [
      credo: [enabled: false],
      dialyzer: [enabled: false],
      doctor: [enabled: false],
      gettext: [enabled: false],
      sobelow: [enabled: false],
      dependencies: [enabled: false],
      test: [coverage: false]
    ]

    defp with_custom(entries, extra \\ []) do
      base = Keyword.merge([custom: entries] ++ @quiet, extra)

      ExQuality.Config
      |> stub(:load, fn opts ->
        opts
        |> Keyword.get_values(:skip)
        |> Enum.reduce(base, fn key, config ->
          Keyword.put(config, String.to_atom(key),
            enabled: false,
            disabled_by: {:cli, "--skip #{key}"}
          )
        end)
      end)
    end

    defp stub_quiet_run(extra \\ fn _cmd, _args, _opts -> nil end) do
      System
      |> stub(:cmd, fn cmd, args, opts ->
        case extra.(cmd, args, opts) do
          nil -> quiet_cmd(cmd, args)
          result -> result
        end
      end)
    end

    defp quiet_cmd("mix", ["test" | _]), do: {"1 tests, 0 failures\n", 0}
    defp quiet_cmd(_cmd, _args), do: {"", 0}

    test "a command stage runs and reports its findings" do
      path = Path.join(System.tmp_dir!(), "quality-#{System.unique_integer([:positive])}.json")
      on_exit(fn -> File.rm(path) end)

      document =
        Jason.encode!(%{
          "summary" => "1 unsound claim",
          "findings" => [
            %{
              "file" => "lib/my_app/contact.ex",
              "line" => 14,
              "severity" => "error",
              "check" => "unsound",
              "message" => "field :email is typed non-nil but the column is nullable"
            }
          ]
        })

      with_custom([
        [
          key: :nullability,
          name: "Nullability",
          command: "mix",
          args: ["schema.nullability", "--format", "json"]
        ]
      ])

      stub_quiet_run(fn
        "mix", ["schema.nullability" | _], _opts -> {document, 1}
        _cmd, _args, _opts -> nil
      end)

      captured = capture_io(fn -> run_failing(["--report", path]) end)

      assert captured =~
               "lib/my_app/contact.ex\n  14  [error] field :email is typed non-nil " <>
                 "but the column is nullable (unsound)"

      report = path |> File.read!() |> Jason.decode!()
      stage = Enum.find(report["stages"], &(&1["name"] == "Nullability"))

      assert stage["status"] == "error"
      assert stage["summary"] == "1 unsound claim"
      assert [%{"file" => "lib/my_app/contact.ex", "check" => "unsound"}] = stage["findings"]
    end

    test "a module stage runs" do
      with_custom([[key: :house_rules, name: "House rules", module: HouseRules]])
      stub_quiet_run()

      assert capture_io(fn -> Quality.run([]) end) =~ "✓ House rules: Nothing to say"
    end

    test "a custom stage appears in the JSON report like any other" do
      path = Path.join(System.tmp_dir!(), "quality-#{System.unique_integer([:positive])}.json")
      on_exit(fn -> File.rm(path) end)

      with_custom([[key: :house_rules, name: "House rules", module: HouseRules]])
      stub_quiet_run()

      capture_io(fn -> Quality.run(["--report", path]) end)

      report = path |> File.read!() |> Jason.decode!()
      stage = Enum.find(report["stages"], &(&1["name"] == "House rules"))

      assert stage["status"] == "ok"
      assert stage["summary"] == "Nothing to say"
    end

    test "--skip names a custom stage, which has no --skip-<key> of its own" do
      with_custom([[key: :nullability, name: "Nullability", command: "mix"]])
      stub_quiet_run()

      captured = capture_io(fn -> Quality.run(["--skip", "nullability"]) end)

      assert captured =~ "○ Nullability: skipped (--skip nullability)"
      refute captured =~ "✓ Nullability"
    end

    test "--skip works for a built-in stage too" do
      with_custom([], credo: [enabled: true, available: true])
      stub_quiet_run()

      captured = capture_io(fn -> Quality.run(["--skip", "credo"]) end)

      assert captured =~ "○ Credo: skipped (--skip credo)"
    end

    test "enabled: false in the entry skips it and names the file" do
      with_custom([[key: :nullability, name: "Nullability", command: "mix", enabled: false]])
      stub_quiet_run()

      captured = capture_io(fn -> Quality.run([]) end)

      assert captured =~ "○ Nullability: skipped (disabled in .quality.exs)"
    end

    test "a custom writer finishes before any reader starts" do
      with_custom([
        [key: :codegen, name: "Codegen", command: "mix", args: ["gen.all"], kind: :writer]
      ])

      test_pid = self()

      stub_quiet_run(fn
        "mix", ["gen.all"], _opts ->
          send(test_pid, {:cmd, :codegen_started})
          Process.sleep(50)
          send(test_pid, {:cmd, :codegen_finished})
          {"", 0}

        "mix", ["test" | _], _opts ->
          send(test_pid, {:cmd, :test_started})
          {"1 tests, 0 failures\n", 0}

        _cmd, _args, _opts ->
          nil
      end)

      capture_io(fn -> Quality.run([]) end)

      events = drain_events()

      assert :test_started in events
      assert Enum.take_while(events, &(&1 != :codegen_finished)) == [:codegen_started]
    end

    test "a custom stage survives a failed compile as skipped, with the compile's reason" do
      with_custom([[key: :nullability, name: "Nullability", command: "mix"]])

      stub_quiet_run(fn
        "mix", ["compile" | _], _opts -> {"** (CompileError) boom\n", 1}
        _cmd, _args, _opts -> nil
      end)

      captured = capture_io(fn -> run_failing([]) end)

      assert captured =~ "○ Nullability: skipped (compile failed)"
    end

    test "a command that is not applicable is reported as skipped, not failed" do
      with_custom([
        [key: :nullability, name: "Nullability", command: "mix", skip_exit_code: 2]
      ])

      stub_quiet_run(fn
        "mix", [], _opts -> {"test database is not migrated\n", 2}
        _cmd, _args, _opts -> nil
      end)

      captured = capture_io(fn -> Quality.run([]) end)

      assert captured =~ "○ Nullability: skipped (test database is not migrated)"
      assert captured =~ "All quality checks passed"
    end
  end

  # The runs above fail on purpose; the report is the thing under test, not
  # the exception Mix raises afterwards.
  describe "an inner loop rather than a gate" do
    setup do
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

      :ok
    end

    defp record_commands do
      test_pid = self()

      System
      |> stub(:cmd, fn cmd, args, _opts ->
        send(test_pid, {:ran, args})

        case args do
          ["credo" | _] -> {Jason.encode!(%{issues: []}), 0}
          ["test" | _] -> {"1 tests, 0 failures\n", 0}
          _other when cmd == "git" -> {"", 1}
          _other -> {"", 0}
        end
      end)
    end

    defp ran_commands do
      Enum.reverse(drain_commands([]))
    end

    defp drain_commands(acc) do
      receive do
        {:ran, args} -> drain_commands([args | acc])
      after
        0 -> acc
      end
    end

    test "--profile skips the stages the profile leaves out" do
      ExQuality.Config
      |> stub(:load, fn opts ->
        ExQuality.Config.apply_profile(
          [profiles: [loop: [stages: [:format, :credo]]]],
          opts[:profile]
        )
      end)

      record_commands()

      captured = capture_io(fn -> Quality.run(["--profile", "loop", "--skip-dialyzer"]) end)

      assert captured =~ "○ Tests: skipped (not in profile :loop)"
      assert captured =~ "○ Compile: skipped (not in profile :loop)"
      refute Enum.any?(ran_commands(), &match?(["test" | _], &1))
    end

    test "--test-scope changed narrows the suite the run pays for" do
      record_commands()

      capture_io(fn ->
        run_failing(["--test-scope", "test/ex_quality/scope_test.exs", "--skip-credo"])
      end)

      assert ["test", "test/ex_quality/scope_test.exs"] in ran_commands()
    end

    test "--until-first-failure stops at the first failing stage, cheapest first" do
      test_pid = self()

      System
      |> stub(:cmd, fn _cmd, args, _opts ->
        send(test_pid, {:ran, args})

        case args do
          ["deps.unlock", "--check-unused"] -> {"Unused deps: :leftover\n", 1}
          ["credo" | _] -> {Jason.encode!(%{issues: []}), 0}
          ["test" | _] -> {"1 tests, 0 failures\n", 0}
          _other -> {"", 0}
        end
      end)

      captured = capture_io(fn -> run_failing(["--until-first-failure"]) end)

      # Dependencies is the cheapest stage after the two that have to go first,
      # so credo and the suite are never paid for.
      commands = ran_commands()

      refute Enum.any?(commands, &match?(["test" | _], &1))
      refute Enum.any?(commands, &match?(["credo" | _], &1))

      assert captured =~ "○ Tests: skipped (--until-first-failure)"
      assert captured =~ "○ Credo: skipped (--until-first-failure)"
    end

    test "--until-first-failure runs everything when nothing fails" do
      record_commands()

      captured = capture_io(fn -> Quality.run(["--until-first-failure"]) end)

      commands = ran_commands()

      assert Enum.any?(commands, &match?(["test" | _], &1))
      assert Enum.any?(commands, &match?(["credo" | _], &1))
      assert captured =~ "✓ All quality checks passed!"
    end

    test "--report - puts the report on stdout and the human stream on stderr" do
      record_commands()

      captured = capture_io(fn -> Quality.run(["--report", "-"]) end)

      report = Jason.decode!(captured)

      assert report["status"] == "ok"
      assert report["scope"] == "all"
      assert report["profile"] == nil
    end

    test "a scoped run says so in the report root and on the Tests stage" do
      record_commands()

      captured =
        capture_io(fn -> Quality.run(["--report", "-", "--test-scope", "test/*_test.exs"]) end)

      report = Jason.decode!(captured)
      tests = Enum.find(report["stages"], &(&1["name"] == "Tests"))

      assert report["scope"] == "test/*_test.exs"
      assert tests["scope"] == "test/*_test.exs"
      assert tests["coverage"] == "skipped"
      assert tests["test_files"] == ["test/ex_quality_test.exs"]
    end
  end

  defp run_failing(args) do
    Quality.run(args)
  rescue
    Mix.Error -> :ok
  end
end
