defmodule ExQuality.CustomTest do
  use ExUnit.Case, async: true

  alias ExQuality.Custom

  defmodule Runnable do
    @moduledoc false
    def run(_config), do: %{}
  end

  defmodule Writer do
    @moduledoc false
    def run(_config), do: %{}
    def stage_kind(_config), do: :writer
  end

  defmodule NotAStage do
    @moduledoc false
    def check, do: :ok
  end

  defp command_entry(attrs \\ []) do
    Keyword.merge([key: :nullability, name: "Nullability", command: "mix"], attrs)
  end

  defp module_entry(attrs \\ []) do
    Keyword.merge([key: :house_rules, name: "House rules", module: Runnable], attrs)
  end

  describe "stages/1" do
    test "returns the entries in declaration order" do
      entries = [command_entry(), module_entry()]

      assert Enum.map(Custom.stages(custom: entries), &Keyword.fetch!(&1, :key)) ==
               [:nullability, :house_rules]
    end

    test "a config with no custom key has no custom stages" do
      assert Custom.stages([]) == []
    end
  end

  describe "kind/2" do
    test "a command entry is a reader by default" do
      assert Custom.kind(command_entry(), []) == :reader
    end

    test "an entry that declares a kind is taken at its word" do
      assert Custom.kind(command_entry(kind: :writer), []) == :writer
    end

    test "a module entry is asked" do
      assert Custom.kind(module_entry(), []) == :reader
      assert Custom.kind(module_entry(module: Writer), []) == :writer
    end
  end

  describe "runner/1" do
    test "a module entry runs the module" do
      assert Custom.runner(module_entry()).([]) == %{}
    end
  end

  describe "skip_reason/2" do
    test "a stage that will run has no reason" do
      assert Custom.skip_reason([], command_entry()) == nil
    end

    test "enabled: false in the entry names the file" do
      assert Custom.skip_reason([], command_entry(enabled: false)) == "disabled in .quality.exs"
    end

    test "--skip names itself, because there is no --skip-nullability to point at" do
      config = [nullability: [enabled: false, disabled_by: {:cli, "--skip nullability"}]]

      assert Custom.skip_reason(config, command_entry()) == "--skip nullability"
    end
  end

  describe "validate!/1" do
    test "accepts both entry forms" do
      assert Custom.validate!(custom: [command_entry(), module_entry()]) == :ok
    end

    test "accepts a config with no custom stages" do
      assert Custom.validate!([]) == :ok
    end

    test "rejects a missing key" do
      assert_raise Mix.Error, ~r/missing key:/, fn ->
        Custom.validate!(custom: [[name: "Nullability", command: "mix"]])
      end
    end

    test "rejects a missing name" do
      assert_raise Mix.Error, ~r/missing name:/, fn ->
        Custom.validate!(custom: [[key: :nullability, command: "mix"]])
      end
    end

    test "rejects an entry with neither module nor command" do
      assert_raise Mix.Error, ~r/declares neither module: nor command:/, fn ->
        Custom.validate!(custom: [[key: :nullability, name: "Nullability"]])
      end
    end

    test "rejects an entry with both" do
      assert_raise Mix.Error, ~r/declares both module: and command:/, fn ->
        Custom.validate!(custom: [command_entry(module: Runnable)])
      end
    end

    test "rejects a key that shadows a built-in stage" do
      assert_raise Mix.Error, ~r/key :credo is a built-in stage/, fn ->
        Custom.validate!(custom: [command_entry(key: :credo)])
      end
    end

    test "rejects a name that shadows a built-in stage" do
      assert_raise Mix.Error, ~r/name "Credo" is a built-in stage/, fn ->
        Custom.validate!(custom: [command_entry(name: "Credo")])
      end
    end

    test "rejects a duplicate key across entries" do
      assert_raise Mix.Error, ~r/duplicate custom stage key :nullability/, fn ->
        Custom.validate!(custom: [command_entry(), command_entry(name: "Other")])
      end
    end

    test "rejects a kind that is neither reader nor writer" do
      assert_raise Mix.Error, ~r/kind must be :reader or :writer/, fn ->
        Custom.validate!(custom: [command_entry(kind: :whenever)])
      end
    end

    test "rejects a module that cannot be loaded" do
      assert_raise Mix.Error, ~r/could not be loaded/, fn ->
        Custom.validate!(custom: [module_entry(module: NoSuchModule.Anywhere)])
      end
    end

    test "rejects a module that does not export run/1" do
      assert_raise Mix.Error, ~r/does not export run\/1/, fn ->
        Custom.validate!(custom: [module_entry(module: NotAStage)])
      end
    end

    test "rejects args that are not strings" do
      assert_raise Mix.Error, ~r/args must be a list of strings/, fn ->
        Custom.validate!(custom: [command_entry(args: [:schema])])
      end
    end

    test "rejects env that is not string pairs" do
      assert_raise Mix.Error, ~r/env must be a list of/, fn ->
        Custom.validate!(custom: [command_entry(env: [{"MIX_ENV", :test}])])
      end
    end

    test "rejects an unknown parse mode" do
      assert_raise Mix.Error, ~r/parse must be :json or :none/, fn ->
        Custom.validate!(custom: [command_entry(parse: :yaml)])
      end
    end

    test "rejects a non-integer skip_exit_code" do
      assert_raise Mix.Error, ~r/skip_exit_code must be an integer/, fn ->
        Custom.validate!(custom: [command_entry(skip_exit_code: "2")])
      end
    end

    test "rejects a custom: that is not a list of keyword lists" do
      assert_raise Mix.Error, ~r/must be a list of keyword lists/, fn ->
        Custom.validate!(custom: [key: :nullability, name: "Nullability", command: "mix"])
      end
    end

    test "names the offending entry" do
      error =
        assert_raise Mix.Error, fn ->
          Custom.validate!(custom: [command_entry(kind: :whenever)])
        end

      assert Exception.message(error) =~ ~s(key: :nullability)
    end
  end
end
