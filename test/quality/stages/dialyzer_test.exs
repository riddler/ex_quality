defmodule Quality.Stages.DialyzerTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Quality.Stages.Dialyzer

  describe "run/1 - no warnings" do
    setup do
      System
      |> expect(:cmd, fn "mix", ["dialyzer"], _opts ->
        output = """
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
        """

        {output, 0}
      end)

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
  end

  describe "run/1 - warnings found" do
    setup do
      System
      |> expect(:cmd, fn "mix", ["dialyzer"], _opts ->
        output = """
        Proceeding with analysis...

        lib/my_app/user.ex:42:no_return
        Function create/1 has no local return.
        ________________________________________________________________________________
        lib/my_app/api.ex:15:pattern_match
        The pattern can never match the type.
        ________________________________________________________________________________

        Total errors: 2, Skipped: 0, Unnecessary Skips: 0
        done in 0m45.23s
        """

        {output, 2}
      end)

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
  end

  describe "run/1 - single warning" do
    setup do
      System
      |> expect(:cmd, fn "mix", ["dialyzer"], _opts ->
        output = """
        lib/my_app/user.ex:42:no_return
        Function create/1 has no local return.

        Total errors: 1, Skipped: 0
        """

        {output, 1}
      end)

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
      System
      |> expect(:cmd, fn "mix", ["dialyzer"], _opts ->
        output = """
        Could not get Core Erlang code for: /path/to/beam/file.beam
        Recompile with +debug_info or analyze the .erl file instead

        Total errors: 0, Skipped: 2, Unnecessary Skips: 0
        """

        # Exit code 1 but no actual warnings (non-zero for skipped files case)
        {output, 1}
      end)

      :ok
    end

    test "succeeds with skipped files note" do
      result = Dialyzer.run([])

      assert result.status == :ok
      assert result.stats.warning_count == 0
      assert result.summary == "No warnings (some files skipped)"
    end
  end

  describe "run/1 - timing" do
    setup do
      System
      |> expect(:cmd, fn "mix", ["dialyzer"], _opts ->
        Process.sleep(10)
        {"Total errors: 0", 0}
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
      System
      |> expect(:cmd, fn "mix", ["dialyzer"], _opts ->
        {"Total errors: 0", 0}
      end)

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
end
