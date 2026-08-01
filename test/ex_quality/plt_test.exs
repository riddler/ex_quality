defmodule ExQuality.PltTest do
  use ExUnit.Case, async: true

  doctest ExQuality.Plt

  alias ExQuality.Plt

  describe "build_line?/1" do
    test "recognises the lines dialyxir prints while building" do
      assert Plt.build_line?("Creating dialyxir_erlang-25.3_elixir-1.14.5_deps-dev.plt")

      assert Plt.build_line?(
               "Copying dialyxir_erlang-25.3.plt to dialyxir_erlang-25.3_deps-dev.plt"
             )

      assert Plt.build_line?("Adding 1042 modules to dialyxir_erlang-25.3_deps-dev.plt")
      assert Plt.build_line?("Adding 1 module to dialyxir_erlang-25.3_deps-dev.plt")
      assert Plt.build_line?("In an Umbrella child and no PLT found - building that first.")
    end

    test "ignores the lines a warm run prints" do
      refute Plt.build_line?("Checking PLT...")
      refute Plt.build_line?("PLT is up to date!")
      refute Plt.build_line?("Looking up modules in dialyxir_erlang-25.3_deps-dev.plt")
      refute Plt.build_line?("Checking 365 modules in dialyxir_erlang-25.3_deps-dev.plt")
      refute Plt.build_line?("Total errors: 0, Skipped: 0, Unnecessary Skips: 0")
      refute Plt.build_line?("")
    end

    test "tolerates surrounding whitespace" do
      assert Plt.build_line?("  Adding 12 modules to a.plt\r")
    end
  end

  describe "built?/1" do
    test "is true when the output holds a build line" do
      output = """
      Finding suitable PLTs
      Creating dialyxir_erlang-25.3_deps-dev.plt
      Adding 1042 modules to dialyxir_erlang-25.3_deps-dev.plt
      Total errors: 0
      """

      assert Plt.built?(output)
    end

    test "is false for a run against a warm PLT" do
      output = """
      Finding suitable PLTs
      Checking PLT...
      PLT is up to date!
      Checking 365 modules in dialyxir_erlang-25.3_deps-dev.plt
      Total errors: 0
      """

      refute Plt.built?(output)
    end

    test "is false for empty output" do
      refute Plt.built?("")
    end
  end

  describe "build_watcher/1" do
    test "fires on the first build line only" do
      test_pid = self()
      watcher = Plt.build_watcher(fn -> send(test_pid, :building) end)

      watcher.("Checking PLT...")
      refute_received :building

      watcher.("Creating a.plt")
      assert_received :building

      watcher.("Adding 12 modules to a.plt")
      refute_received :building
    end

    test "never fires for a warm run" do
      test_pid = self()
      watcher = Plt.build_watcher(fn -> send(test_pid, :building) end)

      Enum.each(["Checking PLT...", "PLT is up to date!", "Total errors: 0"], watcher)

      refute_received :building
    end
  end
end
