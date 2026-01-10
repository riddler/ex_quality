defmodule ExQuality.Stages.CredoTest do
  use ExUnit.Case, async: true
  use Mimic

  alias ExQuality.Stages.Credo

  describe "run/1 - no issues found" do
    setup do
      System
      |> expect(:cmd, fn "mix", ["credo", "--strict"], _opts ->
        output = """
        Checking 24 source files ...

        Please report incorrect results: https://github.com/rrrene/credo/issues

        Analysis took 0.5 seconds (0.1s to load, 0.4s running 52 checks on 24 files)
        51 mods/funs, found no issues.
        """

        {output, 0}
      end)

      :ok
    end

    test "returns success with zero issues" do
      result = Credo.run([])

      assert result.name == "Credo"
      assert result.status == :ok
      assert result.stats.issue_count == 0
      assert result.summary == "No issues"
      assert is_integer(result.duration_ms)
      assert result.duration_ms >= 0
    end
  end

  describe "run/1 - issues found" do
    setup do
      System
      |> expect(:cmd, fn "mix", ["credo", "--strict"], _opts ->
        output = """
        Checking 24 source files ...

        ┃
        ┃ [W] ↗ Modules should have a @moduledoc tag.
        ┃       lib/my_app/user.ex:15:11 #(MyApp.User)
        ┃
        ┃ [R] ↗ Function body is nested too deep (max depth is 2, was 3).
        ┃       lib/my_app/api.ex:42:3 (MyApp.API.process/1)
        ┃
        ┃ [C] ↗ There should be no calls to IO.inspect/2.
        ┃       lib/my_app/debug.ex:10:5 (MyApp.Debug.check/1)

        Please report incorrect results: https://github.com/rrrene/credo/issues

        Analysis took 0.5 seconds
        51 mods/funs, found 1 warning, 1 refactoring opportunity, 1 consistency issue.
        """

        {output, 1}
      end)

      :ok
    end

    test "returns error with issue count" do
      result = Credo.run([])

      assert result.name == "Credo"
      assert result.status == :error
      assert result.stats.issue_count == 3
      assert result.summary =~ "3 issue"
      assert result.summary =~ "warning"
      assert result.summary =~ "refactoring"
      assert result.summary =~ "consistency"
    end

    test "includes full output with file references" do
      result = Credo.run([])

      assert result.output =~ "lib/my_app/user.ex:15:11"
      assert result.output =~ "lib/my_app/api.ex:42:3"
      assert result.output =~ "lib/my_app/debug.ex:10:5"
    end
  end

  describe "run/1 - multiple issue types" do
    setup do
      System
      |> expect(:cmd, fn "mix", ["credo", "--strict"], _opts ->
        output = """
        Analysis took 0.5 seconds
        51 mods/funs, found 2 warnings, 3 code readability issues, 2 software design suggestions.
        """

        {output, 1}
      end)

      :ok
    end

    test "parses and sums all issue types" do
      result = Credo.run([])

      assert result.status == :error
      assert result.stats.issue_count == 7
      assert result.summary =~ "7 issue"
      assert result.summary =~ "2 warning"
      assert result.summary =~ "3 readability"
      assert result.summary =~ "2 design"
    end
  end

  describe "run/1 - configuration options" do
    test "uses strict mode by default" do
      System
      |> expect(:cmd, fn "mix", ["credo", "--strict"], _opts ->
        {"No issues", 0}
      end)

      result = Credo.run([])

      assert result.status == :ok
    end

    test "respects strict: false config" do
      System
      |> expect(:cmd, fn "mix", ["credo"], _opts ->
        {"No issues", 0}
      end)

      result = Credo.run(credo: [strict: false])

      assert result.status == :ok
    end

    test "respects all: true config" do
      System
      |> expect(:cmd, fn "mix", ["credo", "--strict", "--all"], _opts ->
        {"No issues", 0}
      end)

      result = Credo.run(credo: [strict: true, all: true])

      assert result.status == :ok
    end

    test "handles non-strict with all" do
      System
      |> expect(:cmd, fn "mix", ["credo", "--all"], _opts ->
        {"No issues", 0}
      end)

      result = Credo.run(credo: [strict: false, all: true])

      assert result.status == :ok
    end
  end

  describe "run/1 - fallback issue counting" do
    setup do
      # Output without summary line - fallback to counting issue markers
      System
      |> expect(:cmd, fn "mix", ["credo", "--strict"], _opts ->
        output = """
        ┃ [W] ↗ Issue 1
        ┃ [R] ↗ Issue 2
        ┃ [C] ↗ Issue 3
        ┃ [F] ↗ Issue 4
        ┃ [D] ↗ Issue 5
        """

        {output, 1}
      end)

      :ok
    end

    test "counts issue markers when summary not found" do
      result = Credo.run([])

      assert result.status == :error
      assert result.stats.issue_count == 5
    end
  end

  describe "run/1 - single issue" do
    setup do
      System
      |> expect(:cmd, fn "mix", ["credo", "--strict"], _opts ->
        output = """
        51 mods/funs, found 1 refactoring opportunity.
        """

        {output, 1}
      end)

      :ok
    end

    test "formats singular issue correctly" do
      result = Credo.run([])

      assert result.status == :error
      assert result.stats.issue_count == 1
      assert result.summary == "1 issue(s) (1 refactoring)"
    end
  end

  describe "run/1 - timing" do
    setup do
      System
      |> expect(:cmd, fn "mix", ["credo", "--strict"], _opts ->
        Process.sleep(10)
        {"No issues", 0}
      end)

      :ok
    end

    test "records execution duration" do
      result = Credo.run([])

      assert result.duration_ms >= 10
      assert result.duration_ms < 5_000
    end
  end

  describe "run/1 - empty config" do
    setup do
      System
      |> expect(:cmd, fn "mix", ["credo", "--strict"], _opts ->
        {"No issues", 0}
      end)

      :ok
    end

    test "handles empty config" do
      result = Credo.run([])

      assert result.status == :ok
    end
  end
end
