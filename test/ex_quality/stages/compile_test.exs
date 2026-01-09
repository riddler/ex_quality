defmodule ExQuality.Stages.CompileTest do
  use ExUnit.Case, async: true
  use Mimic

  alias ExQuality.Stages.Compile

  describe "run/1 - successful compilation" do
    setup do
      # Mock successful compilation for both dev and test environments
      System
      |> stub(:cmd, fn "mix", args, opts ->
        env = Keyword.get(opts, :env, [])
        {_, mix_env} = List.keyfind(env, "MIX_ENV", 0, {"MIX_ENV", "dev"})

        output = """
        Compiling 15 files (.ex)
        Generated my_app app
        """

        case {args, mix_env} do
          {["compile", "--warnings-as-errors"], "dev"} -> {output, 0}
          {["compile", "--warnings-as-errors"], "test"} -> {output, 0}
          {["compile"], "dev"} -> {output, 0}
          {["compile"], "test"} -> {output, 0}
          _ -> {"Unexpected command", 1}
        end
      end)

      :ok
    end

    test "returns success result with both environments compiled" do
      result = Compile.run([])

      assert result.name == "Compile"
      assert result.status == :ok
      assert result.summary =~ "dev + test compiled"
      assert result.summary =~ "warnings as errors"
      assert result.stats == %{}
      assert is_integer(result.duration_ms)
      assert result.duration_ms >= 0
    end

    test "filters out boring compilation lines from output" do
      result = Compile.run([])

      # Success output should be empty because we filter boring lines
      assert result.output == ""
    end

    test "respects warnings_as_errors config" do
      config = [compile: [warnings_as_errors: true]]
      result = Compile.run(config)

      assert result.status == :ok
      assert result.summary =~ "warnings as errors"
    end

    test "omits warnings note when warnings_as_errors is false" do
      config = [compile: [warnings_as_errors: false]]
      result = Compile.run(config)

      assert result.status == :ok
      refute result.summary =~ "warnings as errors"
      assert result.summary =~ "dev + test compiled"
    end
  end

  describe "run/1 - dev compilation failure" do
    setup do
      # Mock dev failure, test success
      System
      |> stub(:cmd, fn "mix", _args, opts ->
        env = Keyword.get(opts, :env, [])
        {_, mix_env} = List.keyfind(env, "MIX_ENV", 0, {"MIX_ENV", "dev"})

        case mix_env do
          "dev" ->
            output = """
            Compiling 15 files (.ex)

            == Compilation error in file lib/my_app/user.ex ==
            ** (CompileError) lib/my_app/user.ex:42: undefined function foo/1
                (elixir 1.14.0) lib/kernel/parallel_compiler.ex:347
            """

            {output, 1}

          "test" ->
            {"Compiled in 0.5s", 0}
        end
      end)

      :ok
    end

    test "returns error with dev in name" do
      result = Compile.run([])

      assert result.name == "Compile (dev)"
      assert result.status == :error
      assert result.summary == "dev compilation failed"
      assert result.output =~ "CompileError"
      assert result.output =~ "lib/my_app/user.ex:42"
    end

    test "includes full error output" do
      result = Compile.run([])

      assert result.output =~ "undefined function foo/1"
      assert is_binary(result.output)
    end
  end

  describe "run/1 - test compilation failure" do
    setup do
      # Mock dev success, test failure
      System
      |> stub(:cmd, fn "mix", _args, opts ->
        env = Keyword.get(opts, :env, [])
        {_, mix_env} = List.keyfind(env, "MIX_ENV", 0, {"MIX_ENV", "dev"})

        case mix_env do
          "dev" ->
            {"Compiled in 0.5s", 0}

          "test" ->
            output = """
            Compiling 5 files (.ex)

            == Compilation error in file test/my_app_test.exs ==
            ** (CompileError) test/my_app_test.exs:15: undefined function bar/2
            """

            {output, 1}
        end
      end)

      :ok
    end

    test "returns error with test in name" do
      result = Compile.run([])

      assert result.name == "Compile (test)"
      assert result.status == :error
      assert result.summary == "test compilation failed"
      assert result.output =~ "CompileError"
      assert result.output =~ "test/my_app_test.exs:15"
    end
  end

  describe "run/1 - compilation with warnings (treated as errors)" do
    setup do
      # Mock compilation with warnings
      System
      |> stub(:cmd, fn "mix", _args, opts ->
        env = Keyword.get(opts, :env, [])
        {_, mix_env} = List.keyfind(env, "MIX_ENV", 0, {"MIX_ENV", "dev"})

        output = """
        Compiling 15 files (.ex)
        warning: variable "unused_var" is unused (if the variable is not meant to be used, prefix it with an underscore)
          lib/my_app/user.ex:42

        """

        case mix_env do
          "dev" -> {output, 1}
          "test" -> {output, 0}
        end
      end)

      :ok
    end

    test "fails when warnings_as_errors is true (default)" do
      result = Compile.run([])

      assert result.status == :error
      assert result.name == "Compile (dev)"
      assert result.output =~ "warning:"
      assert result.output =~ "lib/my_app/user.ex:42"
    end
  end

  describe "run/1 - output with interesting information" do
    setup do
      # Mock compilation with some interesting output (not just boring lines)
      System
      |> stub(:cmd, fn "mix", _args, opts ->
        env = Keyword.get(opts, :env, [])
        {_, _mix_env} = List.keyfind(env, "MIX_ENV", 0, {"MIX_ENV", "dev"})

        output = """
        Compiling 15 files (.ex)
        Generated my_app app
        ==> some_dependency
        Compiling 5 files (.ex)
        Custom build step completed
        Generated some_dependency app
        Compiled in 1.5s
        """

        {output, 0}
      end)

      :ok
    end

    test "includes interesting output sections" do
      result = Compile.run([])

      # Should filter out boring lines but keep interesting ones
      # In this case, "==> some_dependency" and "Custom build step completed" are interesting
      assert result.status == :ok

      # The format_success_output function filters out boring lines
      # Non-boring lines like "Custom build step completed" should be kept
      assert result.output =~ "Custom build step completed"
      assert result.output =~ "==> some_dependency"
    end
  end

  describe "run/1 - parallel execution timing" do
    setup do
      # Mock with delays to verify parallel execution
      System
      |> stub(:cmd, fn "mix", _args, opts ->
        env = Keyword.get(opts, :env, [])
        {_, mix_env} = List.keyfind(env, "MIX_ENV", 0, {"MIX_ENV", "dev"})

        # Each compilation takes 50ms
        Process.sleep(50)

        case mix_env do
          "dev" -> {"Compiled dev", 0}
          "test" -> {"Compiled test", 0}
        end
      end)

      :ok
    end

    test "runs both compilations in parallel" do
      start_time = System.monotonic_time(:millisecond)
      result = Compile.run([])
      end_time = System.monotonic_time(:millisecond)

      actual_duration = end_time - start_time

      # If running in parallel, total time should be ~50ms (one compilation time)
      # If running sequentially, total time would be ~100ms (two compilation times)
      # Allow some overhead for process spawning
      assert actual_duration < 80

      # Result's recorded duration should match actual duration
      assert abs(result.duration_ms - actual_duration) < 20

      assert result.status == :ok
    end
  end

  describe "run/1 - configuration handling" do
    setup do
      System
      |> stub(:cmd, fn "mix", _args, _opts ->
        {"Compiled", 0}
      end)

      :ok
    end

    test "handles empty config" do
      result = Compile.run([])

      assert result.status == :ok
      assert is_map(result)
    end

    test "handles compile config block" do
      config = [compile: [warnings_as_errors: true]]
      result = Compile.run(config)

      assert result.status == :ok
    end

    test "handles nil values gracefully" do
      config = [compile: [warnings_as_errors: nil]]

      # warnings_as_errors defaults to true, so nil would use default
      # But we're mocking, so this just verifies no crash
      result = Compile.run(config)

      assert result.status == :ok
    end
  end

  describe "run/1 - records empty stats" do
    setup do
      System
      |> stub(:cmd, fn "mix", _args, _opts ->
        {"Compiled", 0}
      end)

      :ok
    end

    test "stats map is always empty" do
      result = Compile.run([])

      assert result.stats == %{}
    end
  end
end
