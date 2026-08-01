defmodule ExQuality.Stages.DialyzerTest do
  # Not async: attributing an app-relative path to an app is done by looking
  # for the file, so those tests run from a tree of their own.
  use ExUnit.Case, async: false
  use Mimic

  import ExUnit.CaptureIO

  alias ExQuality.Stages.Dialyzer

  # The stage streams output into a collector so it can report a PLT build while
  # it happens, so the stub has to write there rather than just return the text.
  defp stub_dialyzer(output, exit_code) do
    System
    |> expect(:cmd, fn "mix",
                       ["dialyzer", "--no-compile", "--format", "short", "--format", "dialyxir"],
                       opts ->
      _collected = Enum.into([output], opts[:into])
      {opts[:into], exit_code}
    end)
  end

  describe "run/1 - no warnings" do
    setup do
      stub_dialyzer(
        """
        Finding suitable PLTs
        Checking PLT...
        [:compiler, :elixir, :kernel, :logger, :stdlib]
        Looking up modules in dialyxir_erlang-25.3_elixir-1.14.5_deps-dev.plt
        Finding applications for dialyxir_erlang-25.3_elixir-1.14.5_deps-dev.plt
        Finding modules for dialyxir_erlang-25.3_elixir-1.14.5_deps-dev.plt
        Checking 365 modules in dialyxir_erlang-25.3_elixir-1.14.5_deps-dev.plt
        Done in 0.58s
        done (passed successfully)
        done (passed successfully)
        Proceeding with analysis...

        Total errors: 0, Skipped: 0, Unnecessary Skips: 0
        done in 0m1.23s
        """,
        0
      )

      :ok
    end

    test "returns success with no warnings" do
      result = Dialyzer.run([])

      assert result.name == "Dialyzer"
      assert result.status == :ok
      assert result.stats.warning_count == 0
      assert result.summary == "No warnings"
      assert is_integer(result.duration_ms)
      assert result.duration_ms >= 0
    end

    test "does not report a PLT build for a warm PLT" do
      result = Dialyzer.run([])

      refute Map.has_key?(result.stats, :plt_built)
    end
  end

  describe "run/1 - warnings found" do
    setup do
      stub_dialyzer(
        """
        Proceeding with analysis...

        lib/my_app/user.ex:42:5:no_return Function create/1 has no local return.
        lib/my_app/api.ex:15:pattern_match The pattern can never match the type.

        Total errors: 2, Skipped: 0, Unnecessary Skips: 0
        done in 0m45.23s
        """,
        2
      )

      :ok
    end

    test "returns error with warning count" do
      result = Dialyzer.run([])

      assert result.name == "Dialyzer"
      assert result.status == :error
      assert result.stats.warning_count == 2
      assert result.summary == "2 warnings"
    end

    test "includes file references in output" do
      result = Dialyzer.run([])

      assert result.output =~ "lib/my_app/user.ex:42"
      assert result.output =~ "lib/my_app/api.ex:15"
    end

    test "parses each warning into a finding naming the warning" do
      assert [api, user] = ExQuality.Stage.findings(Dialyzer.run([]))

      assert %ExQuality.Finding{
               file: "lib/my_app/user.ex",
               line: 42,
               column: 5,
               severity: :error,
               check: "no_return",
               message: "Function create/1 has no local return."
             } = user

      assert %{file: "lib/my_app/api.ex", line: 15, column: nil, check: "pattern_match"} = api
    end

    test "keeps the line each finding came from" do
      [_api, user] = ExQuality.Stage.findings(Dialyzer.run([]))

      assert user.raw =~ "lib/my_app/user.ex:42:5:no_return"
    end
  end

  describe "run/1 - lines that are not warnings" do
    setup do
      stub_dialyzer(
        """
        Finding suitable PLTs
        Checking 365 modules in dialyxir_erlang-25.3_elixir-1.14.5_deps-dev.plt
        Creating dialyxir_erlang-25.3_elixir-1.14.5_deps-dev.plt
        Could not get Core Erlang code for: /path/to/beam/file.beam
        Proceeding with analysis...
        lib/my_app/user.ex:42:5:no_return Function create/1 has no local return.
        Total errors: 1, Skipped: 0, Unnecessary Skips: 0
        done in 4m12.03s
        """,
        1
      )

      :ok
    end

    test "counts the warnings, not the chatter around them" do
      capture_io(fn -> send(self(), {:result, Dialyzer.run([])}) end)
      assert_received {:result, result}

      assert result.stats.warning_count == 1
      assert [%{check: "no_return"}] = ExQuality.Stage.findings(result)
    end
  end

  describe "run/1 - both formats" do
    setup do
      # What dialyxir prints for one warning when asked for both formats: the
      # short line, then the same warning explained at length.
      stub_dialyzer(
        """
        Proceeding with analysis...

        lib/my_app/user.ex:42:5:no_return Function create/1 has no local return.
        lib/my_app/user.ex:42:5:no_return
        Function create/1 has no local return.

        The success typing is:
        @spec create(map()) :: none()
        ________________________________________________________________________________

        Total errors: 1, Skipped: 0, Unnecessary Skips: 0
        """,
        1
      )

      :ok
    end

    test "counts the warning once, not once per format" do
      result = Dialyzer.run([])

      assert result.stats.warning_count == 1
      assert result.summary == "1 warning"
      assert [%{check: "no_return", column: 5}] = ExQuality.Stage.findings(result)
    end

    test "keeps the long explanation in the output" do
      result = Dialyzer.run([])

      assert result.output =~ "The success typing is:"
      assert result.output =~ "@spec create(map()) :: none()"
    end
  end

  describe "run/1 - umbrella" do
    setup do
      stub_dialyzer(
        """
        apps/web/lib/user.ex:42:5:no_return Function create/1 has no local return.
        lib/root.ex:1:unknown_function Function Foo.bar/0 does not exist.
        """,
        1
      )

      :ok
    end

    test "tags each finding with the app its file belongs to" do
      ExQuality.Umbrella
      |> stub(:apps_paths, fn -> %{web: "apps/web"} end)

      assert [web, root] = ExQuality.Stage.findings(Dialyzer.run([]))

      assert web.app == :web
      assert root.app == nil
    end
  end

  describe "run/1 - umbrella paths relative to a child app" do
    # dialyxir running once from an umbrella root prints each path relative to
    # the app it found the file in, with no header saying which app that was.
    setup do
      stub_dialyzer(
        """
        lib/core/integrations.ex:65:29:unknown_type Unknown type: Core.User.t/0.
        lib/application.ex:1:no_return Function start/2 has no local return.
        lib/nowhere.ex:3:unknown_type Unknown type: Gone.t/0.
        """,
        1
      )

      :ok
    end

    test "resolves the path against the app that has the file, and names it" do
      files = ["apps/core/lib/core/integrations.ex", "apps/web/lib/application.ex"]

      in_project(files, fn ->
        assert [integrations, application, nowhere] = ExQuality.Stage.findings(Dialyzer.run([]))

        assert integrations.app == :core
        assert integrations.file == "apps/core/lib/core/integrations.ex"

        assert application.app == :web
        assert application.file == "apps/web/lib/application.ex"

        # No app has it, so nothing is invented: the path is left as dialyxir
        # reported it.
        assert nowhere.app == nil
        assert nowhere.file == "lib/nowhere.ex"
      end)
    end

    test "does not guess when two apps have the same relative path" do
      files = ["apps/core/lib/application.ex", "apps/web/lib/application.ex"]

      in_project(files, fn ->
        findings = ExQuality.Stage.findings(Dialyzer.run([]))
        application = Enum.find(findings, &(&1.file =~ "application.ex"))

        assert application.app == nil
        assert application.file == "lib/application.ex"
      end)
    end
  end

  # Runs `fun` from a tree that is an umbrella containing exactly these files.
  defp in_project(files, fun) do
    root = Path.join(System.tmp_dir!(), "ex_quality-dialyzer-#{System.unique_integer([:positive])}")

    Enum.each(files, fn path ->
      full = Path.join(root, path)
      File.mkdir_p!(Path.dirname(full))
      File.write!(full, "")
    end)

    stub(ExQuality.Umbrella, :apps_paths, fn -> %{core: "apps/core", web: "apps/web"} end)

    File.mkdir_p!(root)
    cwd = File.cwd!()

    try do
      File.cd!(root, fun)
    after
      File.cd!(cwd)
      File.rm_rf!(root)
    end
  end

  describe "run/1 - single warning" do
    setup do
      stub_dialyzer(
        """
        lib/my_app/user.ex:42:5:no_return Function create/1 has no local return.

        Total errors: 1, Skipped: 0
        """,
        1
      )

      :ok
    end

    test "formats singular warning correctly" do
      result = Dialyzer.run([])

      assert result.status == :error
      assert result.stats.warning_count == 1
      assert result.summary == "1 warning"
    end
  end

  describe "run/1 - with skipped files" do
    setup do
      stub_dialyzer(
        """
        Could not get Core Erlang code for: /path/to/beam/file.beam
        Recompile with +debug_info or analyze the .erl file instead

        Total errors: 0, Skipped: 2, Unnecessary Skips: 0
        """,
        # Exit code 1 but no actual warnings (non-zero for skipped files case)
        1
      )

      :ok
    end

    test "succeeds with skipped files note" do
      result = Dialyzer.run([])

      assert result.status == :ok
      assert result.stats.warning_count == 0
      assert result.summary == "No warnings (some files skipped)"
    end
  end

  describe "run/1 - analysis that never ran" do
    setup do
      # What dialyxir prints when the beams are rewritten under it: the same
      # debug_info error as a genuine skip, but no tally, because it stopped
      # before it had one.
      stub_dialyzer(
        """
        Finding suitable PLTs
        Proceeding with analysis...
        Could not get Core Erlang code for: /path/to/build/dev/lib/web/ebin/Elixir.Web.beam
        Recompile with +debug_info or analyze the .erl file instead
        """,
        1
      )

      :ok
    end

    test "fails rather than passing on an analysis that produced no tally" do
      result = Dialyzer.run([])

      assert result.status == :error
      assert result.summary == "Analysis did not complete (build changed under it? see output)"
    end

    test "carries the tool's output verbatim" do
      assert Dialyzer.run([]).output =~ "Could not get Core Erlang code"
    end
  end

  describe "run/1 - PLT build" do
    setup do
      stub_dialyzer(
        """
        Finding suitable PLTs
        Checking PLT...
        Looking up modules in dialyxir_erlang-25.3_elixir-1.14.5_deps-dev.plt
        Finding applications for dialyxir_erlang-25.3_elixir-1.14.5_deps-dev.plt
        Finding modules for dialyxir_erlang-25.3_elixir-1.14.5_deps-dev.plt
        Creating dialyxir_erlang-25.3_elixir-1.14.5_deps-dev.plt
        Adding 1042 modules to dialyxir_erlang-25.3_elixir-1.14.5_deps-dev.plt
        done in 4m12.03s
        Proceeding with analysis...

        Total errors: 0, Skipped: 0, Unnecessary Skips: 0
        """,
        0
      )

      :ok
    end

    test "still passes on the analysis alone, and says the PLT was built" do
      capture_io(fn -> send(self(), {:result, Dialyzer.run([])}) end)
      assert_received {:result, result}

      assert result.status == :ok
      assert result.stats.plt_built == true
      assert result.summary == "No warnings (PLT built this run)"
    end

    test "announces the build while it is running" do
      output = capture_io(fn -> Dialyzer.run([]) end)

      assert output =~ "⋯ Dialyzer: building PLT (this is a one-time cost)"
    end

    test "announces the build once, not once per line of it" do
      output = capture_io(fn -> Dialyzer.run([]) end)

      assert length(String.split(output, "building PLT")) == 2
    end
  end

  describe "run/1 - PLT build with warnings" do
    setup do
      stub_dialyzer(
        """
        Creating dialyxir_erlang-25.3_elixir-1.14.5_deps-dev.plt
        Adding 1042 modules to dialyxir_erlang-25.3_elixir-1.14.5_deps-dev.plt
        Proceeding with analysis...

        lib/my_app/user.ex:42:5:no_return Function create/1 has no local return.

        Total errors: 1, Skipped: 0
        """,
        1
      )

      :ok
    end

    test "reports the build alongside the failure" do
      capture_io(fn -> send(self(), {:result, Dialyzer.run([])}) end)
      assert_received {:result, result}

      assert result.status == :error
      assert result.stats.warning_count == 1
      assert result.stats.plt_built == true
      assert result.summary == "1 warning (PLT built this run)"
    end
  end

  describe "run/1 - timing" do
    setup do
      System
      |> expect(:cmd, fn "mix",
                         ["dialyzer", "--no-compile", "--format", "short", "--format", "dialyxir"],
                         opts ->
        Process.sleep(10)
        _collected = Enum.into(["Total errors: 0"], opts[:into])
        {opts[:into], 0}
      end)

      :ok
    end

    test "records execution duration" do
      result = Dialyzer.run([])

      assert result.duration_ms >= 10
      assert result.duration_ms < 5_000
    end
  end

  describe "run/1 - configuration" do
    setup do
      stub_dialyzer("Total errors: 0", 0)

      :ok
    end

    test "handles empty config" do
      result = Dialyzer.run([])

      assert result.status == :ok
    end

    test "ignores config options" do
      result = Dialyzer.run(some_option: true)

      assert result.status == :ok
    end
  end

  describe "run/1 - unknown failure" do
    setup do
      stub_dialyzer("Dialyzer could not start: something went wrong", 1)

      :ok
    end

    test "reports the failure rather than an empty pass" do
      result = Dialyzer.run([])

      assert result.status == :error
      assert result.summary == "Check failed (see output)"
    end
  end
end
