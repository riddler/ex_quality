defmodule ExQuality.Stages.CredoTest do
  use ExUnit.Case, async: true
  use Mimic

  alias ExQuality.Stages.Credo

  @args ["credo", "--format", "json", "--strict"]

  defp report(issues), do: Jason.encode!(%{"issues" => issues}, pretty: true)

  defp issue(attrs) do
    Map.merge(
      %{
        "check" => "Credo.Check.Readability.ModuleDoc",
        "category" => "readability",
        "filename" => "lib/my_app/user.ex",
        "line_no" => 15,
        "column" => 11,
        "column_end" => nil,
        "trigger" => "MyApp.User",
        "message" => "Modules should have a @moduledoc tag.",
        "priority" => 1,
        "scope" => "MyApp.User"
      },
      attrs
    )
  end

  describe "run/1 - no issues found" do
    setup do
      System
      |> expect(:cmd, fn "mix", @args, _opts -> {report([]), 0} end)

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
      issues = [
        issue(%{
          "check" => "Credo.Check.Warning.IoInspect",
          "category" => "warning",
          "filename" => "lib/my_app/debug.ex",
          "line_no" => 10,
          "column" => 5,
          "message" => "There should be no calls to IO.inspect/2."
        }),
        issue(%{}),
        issue(%{
          "check" => "Credo.Check.Refactor.Nesting",
          "category" => "refactor",
          "filename" => "lib/my_app/api.ex",
          "line_no" => 42,
          "column" => 3,
          "message" => "Function body is nested too deep (max depth is 2, was 3)."
        })
      ]

      System
      |> expect(:cmd, fn "mix", @args, _opts -> {report(issues), 1} end)

      :ok
    end

    test "returns error with issue count" do
      result = Credo.run([])

      assert result.name == "Credo"
      assert result.status == :error
      assert result.stats.issue_count == 3
      assert result.summary == "3 issues (1 warning, 1 refactor, 1 readability)"
    end

    test "parses issues into findings, sorted by file and line" do
      result = Credo.run([])

      assert [api, debug, user] = ExQuality.Stage.findings(result)

      assert %ExQuality.Finding{
               file: "lib/my_app/user.ex",
               line: 15,
               column: 11,
               severity: :info,
               check: "Credo.Check.Readability.ModuleDoc",
               message: "Modules should have a @moduledoc tag."
             } = user

      assert %{file: "lib/my_app/api.ex", line: 42, column: 3} = api
      assert %{file: "lib/my_app/debug.ex", line: 10, column: 5} = debug
    end

    test "names the check module rather than its category" do
      [api, debug, _user] = ExQuality.Stage.findings(Credo.run([]))

      assert api.check == "Credo.Check.Refactor.Nesting"
      assert debug.check == "Credo.Check.Warning.IoInspect"
    end

    test "reports a warning as a warning and everything else as informational" do
      [api, debug, user] = ExQuality.Stage.findings(Credo.run([]))

      assert debug.severity == :warning
      assert api.severity == :info
      assert user.severity == :info
    end

    test "keeps the issue each finding came from" do
      [_api, _debug, user] = ExQuality.Stage.findings(Credo.run([]))

      assert user.raw =~ "Modules should have a @moduledoc tag."
      assert user.raw =~ "lib/my_app/user.ex"
    end
  end

  describe "run/1 - findings" do
    test "reports no findings when the run passes" do
      System
      |> expect(:cmd, fn "mix", @args, _opts -> {report([]), 0} end)

      assert ExQuality.Stage.findings(Credo.run([])) == []
    end

    test "counts one issue as one" do
      System
      |> expect(:cmd, fn "mix", @args, _opts -> {report([issue(%{})]), 1} end)

      result = Credo.run([])

      assert result.stats.issue_count == 1
      assert result.summary == "1 issue (1 readability)"
    end

    test "reads an issue without a column" do
      System
      |> expect(:cmd, fn "mix", @args, _opts ->
        {report([issue(%{"column" => nil})]), 1}
      end)

      assert [finding] = ExQuality.Stage.findings(Credo.run([]))
      assert %{file: "lib/my_app/user.ex", line: 15, column: nil} = finding
    end

    test "leaves out an entry with no message, which points nowhere" do
      System
      |> expect(:cmd, fn "mix", @args, _opts ->
        {report([%{"filename" => "lib/my_app/user.ex"}]), 1}
      end)

      result = Credo.run([])

      assert ExQuality.Stage.findings(result) == []
      assert result.stats.issue_count == 0
    end

    test "leaves the app unset outside an umbrella" do
      System
      |> expect(:cmd, fn "mix", @args, _opts -> {report([issue(%{})]), 1} end)

      assert [%{app: nil}] = ExQuality.Stage.findings(Credo.run([]))
    end

    test "tags each finding with the umbrella app its file belongs to" do
      ExQuality.Umbrella
      |> stub(:apps_paths, fn -> %{web: "apps/web"} end)

      issues = [
        issue(%{"filename" => "apps/web/lib/user.ex"}),
        issue(%{"filename" => "lib/root.ex"})
      ]

      System
      |> expect(:cmd, fn "mix", @args, _opts -> {report(issues), 1} end)

      assert [web, root] = ExQuality.Stage.findings(Credo.run([]))
      assert web.app == :web
      assert root.app == nil
    end
  end

  describe "run/1 - output that is not a report" do
    test "reads the report out of output the compiler wrote to as well" do
      System
      |> expect(:cmd, fn "mix", @args, _opts ->
        {"Compiling 3 files (.ex)\n" <> report([issue(%{})]), 1}
      end)

      result = Credo.run([])

      assert result.stats.issue_count == 1
      assert [%{file: "lib/my_app/user.ex"}] = ExQuality.Stage.findings(result)
    end

    test "fails loudly when credo printed no report, as an old version does" do
      System
      |> expect(:cmd, fn "mix", @args, _opts ->
        {"** (Mix) Unknown format: json\n", 1}
      end)

      result = Credo.run([])

      assert result.status == :error
      assert result.summary == "Credo did not produce a report"
      assert result.output =~ "Unknown format"
      assert ExQuality.Stage.findings(result) == []
    end

    test "passes when there was nothing to parse and nothing went wrong" do
      System
      |> expect(:cmd, fn "mix", @args, _opts -> {"", 0} end)

      result = Credo.run([])

      assert result.status == :ok
      assert result.summary == "No issues"
    end

    test "fails when credo reported no issues and failed anyway" do
      System
      |> expect(:cmd, fn "mix", @args, _opts -> {report([]), 1} end)

      result = Credo.run([])

      assert result.status == :error
      assert result.summary == "Check failed (see output)"
    end
  end

  describe "run/1 - configuration options" do
    test "uses strict mode by default" do
      System
      |> expect(:cmd, fn "mix", ["credo", "--format", "json", "--strict"], _opts ->
        {report([]), 0}
      end)

      assert Credo.run([]).status == :ok
    end

    test "respects strict: false config" do
      System
      |> expect(:cmd, fn "mix", ["credo", "--format", "json"], _opts -> {report([]), 0} end)

      assert Credo.run(credo: [strict: false]).status == :ok
    end

    test "respects all: true config" do
      System
      |> expect(:cmd, fn "mix", ["credo", "--format", "json", "--strict", "--all"], _opts ->
        {report([]), 0}
      end)

      assert Credo.run(credo: [strict: true, all: true]).status == :ok
    end

    test "handles non-strict with all" do
      System
      |> expect(:cmd, fn "mix", ["credo", "--format", "json", "--all"], _opts ->
        {report([]), 0}
      end)

      assert Credo.run(credo: [strict: false, all: true]).status == :ok
    end
  end

  describe "run/1 - multiple configs" do
    test "runs credo once per named config, in order" do
      System
      |> expect(:cmd, fn "mix", args, _opts ->
        assert args == @args ++ ["--config-name", "default"]
        {report([]), 0}
      end)
      |> expect(:cmd, fn "mix", args, _opts ->
        assert args == @args ++ ["--config-name", "migrations"]
        {report([]), 0}
      end)

      result = Credo.run(credo: [configs: ["default", "migrations"]])

      assert result.status == :ok
      assert result.summary == "No issues"
    end

    test "merges the findings of every config into one result" do
      System
      |> expect(:cmd, fn "mix", _args, _opts -> {report([issue(%{})]), 1} end)
      |> expect(:cmd, fn "mix", _args, _opts ->
        {report([
           issue(%{
             "check" => "Credo.Check.Warning.IoInspect",
             "category" => "warning",
             "filename" => "priv/repo/migrations/001_init.exs",
             "line_no" => 3,
             "message" => "There should be no calls to IO.inspect/2."
           })
         ]), 1}
      end)

      result = Credo.run(credo: [configs: ["default", "migrations"]])

      assert result.status == :error
      assert result.stats.issue_count == 2
      assert result.summary == "2 issues (1 warning, 1 readability)"

      assert Enum.map(ExQuality.Stage.findings(result), & &1.file) == [
               "lib/my_app/user.ex",
               "priv/repo/migrations/001_init.exs"
             ]
    end

    test "counts an issue both configs report once" do
      System
      |> expect(:cmd, 2, fn "mix", _args, _opts -> {report([issue(%{})]), 1} end)

      result = Credo.run(credo: [configs: ["default", "migrations"]])

      assert result.stats.issue_count == 1
      assert result.summary == "1 issue (1 readability)"
      assert [%{file: "lib/my_app/user.ex"}] = ExQuality.Stage.findings(result)
    end

    test "keeps two issues that differ only in check" do
      System
      |> expect(:cmd, fn "mix", _args, _opts -> {report([issue(%{})]), 1} end)
      |> expect(:cmd, fn "mix", _args, _opts ->
        {report([issue(%{"check" => "Credo.Check.Readability.Specs"})]), 1}
      end)

      assert Credo.run(credo: [configs: ["a", "b"]]).stats.issue_count == 2
    end

    test "names the config when a run reported no issues and failed anyway" do
      System
      |> expect(:cmd, fn "mix", _args, _opts -> {report([]), 0} end)
      |> expect(:cmd, fn "mix", _args, _opts -> {report([]), 1} end)

      result = Credo.run(credo: [configs: ["default", "migrations"]])

      assert result.status == :error
      assert result.summary == "Check failed in \"migrations\" (see output)"
    end

    test "names the config when a run printed no report at all" do
      System
      |> expect(:cmd, fn "mix", _args, _opts -> {report([]), 0} end)
      |> expect(:cmd, fn "mix", _args, _opts ->
        {"** (Mix) Unknown config: migrations\n", 1}
      end)

      result = Credo.run(credo: [configs: ["default", "migrations"]])

      assert result.status == :error
      assert result.summary == ~s(Credo did not produce a report in "migrations")
      assert result.output =~ "Unknown config: migrations"
    end

    test "attributes each run's output to the config that produced it" do
      System
      |> expect(:cmd, fn "mix", _args, _opts -> {"first\n", 0} end)
      |> expect(:cmd, fn "mix", _args, _opts -> {"second\n", 0} end)

      result = Credo.run(credo: [configs: ["default", "migrations"]])

      assert result.output =~ "── credo --config-name default ──\nfirst"
      assert result.output =~ "── credo --config-name migrations ──\nsecond"
    end

    test "an empty list runs credo once, as no list does" do
      System
      |> expect(:cmd, fn "mix", @args, _opts -> {report([]), 0} end)

      assert Credo.run(credo: [configs: []]).status == :ok
    end

    test "configs: nil passes the same args as today" do
      System
      |> expect(:cmd, fn "mix", @args, _opts -> {report([]), 0} end)

      result = Credo.run(credo: [configs: nil])

      assert result.status == :ok
      assert result.output == report([])
    end
  end

  describe "run/1 - timing" do
    setup do
      System
      |> expect(:cmd, fn "mix", @args, _opts ->
        Process.sleep(10)
        {report([]), 0}
      end)

      :ok
    end

    test "records execution duration" do
      result = Credo.run([])

      assert result.duration_ms >= 10
      assert result.duration_ms < 5_000
    end
  end
end
