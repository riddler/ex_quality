defmodule ExQuality.AliasesTest do
  # Not async: each test swaps the project Mix reads its aliases from.
  use ExUnit.Case, async: false
  use Mimic

  alias ExQuality.Aliases
  alias ExQuality.Stage
  alias ExQuality.Stages

  doctest ExQuality.Aliases

  defmodule AliasedProject do
    @moduledoc false
    def project do
      [
        app: :aliased,
        aliases: [
          docs: ["docs", "cmd cp -r doc/ priv/static/docs"],
          sobelow: ["cmd --app web mix sobelow --config"],
          "test.coverage": ["test --cover --export-coverage default", "test.coverage"],
          test: ["ecto.create --quiet", "ecto.migrate", "test"]
        ]
      ]
    end
  end

  # Pushes a project whose mix.exs defines the aliases above, so the stages see
  # what they would see in a real project that shadows their tasks.
  defp with_aliases(fun) do
    Mix.Project.push(AliasedProject, "mix.exs")

    try do
      fun.()
    after
      Mix.Project.pop()
    end
  end

  describe "shadowing?/1" do
    test "finds an alias with the task's name" do
      with_aliases(fn ->
        assert Aliases.shadowing?("sobelow")
        assert Aliases.shadowing?("test.coverage")
      end)
    end

    test "does not report a task the project left alone" do
      with_aliases(fn ->
        refute Aliases.shadowing?("credo")
        refute Aliases.shadowing?("dialyzer")
      end)
    end

    test "takes an atom as well as a string" do
      with_aliases(fn ->
        assert Aliases.shadowing?(:sobelow)
      end)
    end
  end

  describe "shadowed/2" do
    test "names the alias and what to do about it" do
      result = Aliases.shadowed("Sobelow", "sobelow")

      assert result.status == :error
      assert result.summary == "mix sobelow is aliased in mix.exs"
      assert result.output =~ "defines a Mix alias named `sobelow`"
      assert result.output =~ "sobelow.all"
      assert Stage.findings(result) == []
    end
  end

  describe "stages refuse to run a task the project has aliased" do
    test "Sobelow says so instead of reporting a missing report" do
      with_aliases(fn ->
        System |> reject(:cmd, 3)

        result = Stages.Sobelow.run([])

        assert result.status == :error
        assert result.summary == "mix sobelow is aliased in mix.exs"
      end)
    end

    test "Docs says so instead of counting warnings from a command it did not issue" do
      with_aliases(fn ->
        System |> reject(:cmd, 3)

        result = Stages.Docs.run([])

        assert result.status == :error
        assert result.summary == "mix docs is aliased in mix.exs"
      end)
    end

    test "Tests says so rather than aggregating a suite it ran twice" do
      with_aliases(fn ->
        stub(ExQuality.Umbrella, :umbrella?, fn -> true end)
        stub(ExQuality.Tools, :available?, fn tool -> tool == :native_coverage end)
        System |> reject(:cmd, 3)

        result = Stages.Test.run(test: [coverage: true])

        assert result.status == :error
        assert result.summary == "mix test.coverage is aliased in mix.exs"
      end)
    end

    test "an aliased mix test is left alone, because running it is correct" do
      with_aliases(fn ->
        stub(ExQuality.Tools, :available?, fn _tool -> false end)

        System
        |> expect(:cmd, fn "mix", ["test"], _opts -> {"1 tests, 0 failures\n", 0} end)

        result = Stages.Test.run([])

        assert result.status == :ok
        assert result.stats.test_count == 1
      end)
    end

    test "Credo runs when the project has not aliased it" do
      with_aliases(fn ->
        System
        |> expect(:cmd, fn "mix", ["credo" | _rest], _opts -> {~s({"issues": []}), 0} end)

        assert Stages.Credo.run([]).status == :ok
      end)
    end
  end
end
