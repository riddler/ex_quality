defmodule ExQuality.Stages.CommandTest do
  use ExUnit.Case, async: true
  use Mimic

  alias ExQuality.Stages.Command

  @entry [key: :nullability, name: "Nullability", command: "mix", args: ["schema.nullability"]]

  defp document(attrs), do: Jason.encode!(attrs, pretty: true)

  defp finding(attrs) do
    Map.merge(
      %{
        "file" => "lib/my_app/contact.ex",
        "line" => 14,
        "severity" => "error",
        "check" => "unsound",
        "message" => "field :email is typed non-nil but the column is nullable"
      },
      attrs
    )
  end

  describe "run/1 - the command itself" do
    test "passes the command, args and env through to System.cmd" do
      System
      |> expect(:cmd, fn "mix", ["schema.nullability", "--format", "json"], opts ->
        assert opts[:env] == [{"MIX_ENV", "test"}]
        assert opts[:stderr_to_stdout]
        refute Keyword.has_key?(opts, :cd)
        {"", 0}
      end)

      entry =
        Keyword.merge(@entry,
          args: ["schema.nullability", "--format", "json"],
          env: [{"MIX_ENV", "test"}]
        )

      assert Command.run(entry).status == :ok
    end

    test "runs in cd when the entry names one" do
      System
      |> expect(:cmd, fn "mix", _args, opts ->
        assert opts[:cd] == "apps/web"
        {"", 0}
      end)

      assert Command.run(Keyword.put(@entry, :cd, "apps/web")).status == :ok
    end

    test "reports a command that could not be run rather than crashing the run" do
      System
      |> expect(:cmd, fn _cmd, _args, _opts -> raise ErlangError, original: :enoent end)

      result = Command.run(@entry)

      assert result.status == :error
      assert result.summary == "Command could not be run"
      assert result.output =~ "mix could not be run"
      assert result.name == "Nullability"
    end
  end

  describe "run/1 - exit codes" do
    test "exit 0 passes" do
      System
      |> expect(:cmd, fn _cmd, _args, _opts -> {"all good\n", 0} end)

      result = Command.run(@entry)

      assert result.status == :ok
      assert result.summary == "Passed"
      assert result.output == "all good\n"
    end

    test "any other exit code fails" do
      System
      |> expect(:cmd, fn _cmd, _args, _opts -> {"boom\n", 3} end)

      result = Command.run(@entry)

      assert result.status == :error
      assert result.summary == "Failed (see output)"
      assert result.output == "boom\n"
    end
  end

  describe "run/1 - the finding contract" do
    test "parses findings out of a JSON document" do
      body =
        document(%{
          "summary" => "2 unsound claims",
          "stats" => %{"finding_count" => 2},
          "findings" => [
            finding(%{"file" => "lib/my_app/user.ex", "line" => 3}),
            finding(%{})
          ]
        })

      System
      |> expect(:cmd, fn _cmd, _args, _opts -> {body, 1} end)

      result = Command.run(@entry)

      assert result.status == :error
      assert result.summary == "2 unsound claims"
      assert result.stats == %{"finding_count" => 2}

      assert [contact, user] = ExQuality.Stage.findings(result)

      assert %{file: "lib/my_app/contact.ex", line: 14, severity: :error, check: "unsound"} =
               contact

      assert %{file: "lib/my_app/user.ex", line: 3} = user
    end

    test "counts the findings when the document gives no summary or stats" do
      System
      |> expect(:cmd, fn _cmd, _args, _opts ->
        {document(%{"findings" => [finding(%{})]}), 1}
      end)

      result = Command.run(@entry)

      assert result.summary == "1 finding"
      assert result.stats == %{"finding_count" => 1}
    end

    test "reads the document out of output the compiler wrote to as well" do
      System
      |> expect(:cmd, fn _cmd, _args, _opts ->
        {"Compiling 3 files (.ex)\n" <> document(%{"findings" => [finding(%{})]}), 1}
      end)

      assert [%{file: "lib/my_app/contact.ex"}] =
               ExQuality.Stage.findings(Command.run(@entry))
    end

    test "leaves out a finding with nowhere to look" do
      System
      |> expect(:cmd, fn _cmd, _args, _opts ->
        {document(%{"findings" => [%{"message" => "something"}, finding(%{})]}), 1}
      end)

      assert [%{file: "lib/my_app/contact.ex"}] =
               ExQuality.Stage.findings(Command.run(@entry))
    end

    test "falls through to output verbatim when nothing parses" do
      System
      |> expect(:cmd, fn _cmd, _args, _opts -> {"** (Mix) no such task\n", 1} end)

      result = Command.run(@entry)

      assert result.status == :error
      assert result.summary == "Failed (see output)"
      assert result.output == "** (Mix) no such task\n"
      assert ExQuality.Stage.findings(result) == []
    end

    test "parse: :none never reads a document, even from output that is one" do
      System
      |> expect(:cmd, fn _cmd, _args, _opts ->
        {document(%{"summary" => "hijacked", "findings" => [finding(%{})]}), 1}
      end)

      result = Command.run(Keyword.put(@entry, :parse, :none))

      assert result.summary == "Failed (see output)"
      assert ExQuality.Stage.findings(result) == []
    end

    test "tags a finding with the umbrella app its file belongs to" do
      ExQuality.Umbrella
      |> stub(:apps_paths, fn -> %{web: "apps/web"} end)

      System
      |> expect(:cmd, fn _cmd, _args, _opts ->
        {document(%{"findings" => [finding(%{"file" => "apps/web/lib/user.ex"})]}), 1}
      end)

      assert [%{app: :web}] = ExQuality.Stage.findings(Command.run(@entry))
    end
  end

  describe "run/1 - skip_exit_code" do
    test "reports the declared exit code as skipped, with the command's own reason" do
      System
      |> expect(:cmd, fn _cmd, _args, _opts ->
        {"\ntest database is not migrated\n", 2}
      end)

      result = Command.run(Keyword.put(@entry, :skip_exit_code, 2))

      assert result.status == :skipped
      assert result.summary == "test database is not migrated"
      assert result.output =~ "not migrated"
    end

    test "says something even when the command exited quietly" do
      System
      |> expect(:cmd, fn _cmd, _args, _opts -> {"", 2} end)

      assert Command.run(Keyword.put(@entry, :skip_exit_code, 2)).summary == "not applicable"
    end

    test "leaves every other exit code alone" do
      System
      |> expect(:cmd, fn _cmd, _args, _opts -> {"boom\n", 1} end)

      assert Command.run(Keyword.put(@entry, :skip_exit_code, 2)).status == :error
    end

    test "without it, a non-zero exit is a failure" do
      System
      |> expect(:cmd, fn _cmd, _args, _opts -> {"not migrated\n", 2} end)

      assert Command.run(@entry).status == :error
    end
  end

  describe "run/1 - timing" do
    test "records execution duration" do
      System
      |> expect(:cmd, fn _cmd, _args, _opts ->
        Process.sleep(10)
        {"", 0}
      end)

      result = Command.run(@entry)

      assert result.duration_ms >= 10
      assert result.duration_ms < 5_000
    end
  end
end
