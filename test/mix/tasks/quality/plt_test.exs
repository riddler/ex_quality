defmodule Mix.Tasks.Quality.PltTest do
  use ExUnit.Case, async: true
  use Mimic

  import ExUnit.CaptureIO

  alias ExQuality.Tools
  alias Mix.Tasks.Quality.Plt

  describe "run/1 with dialyxir installed" do
    setup do
      stub(Tools, :available?, fn :dialyzer -> true end)

      :ok
    end

    test "builds the PLT and reports how long it took" do
      System
      |> expect(:cmd, fn "mix", ["dialyzer", "--plt"], opts ->
        assert opts[:env] == [{"MIX_ENV", "dev"}]
        {opts[:into], 0}
      end)

      output = capture_io(fn -> assert Plt.run([]) == :ok end)

      assert output =~ "Building the Dialyzer PLT. This is a one-time cost."
      assert output =~ "✓ PLT ready"
    end

    test "fails when the build fails" do
      System
      |> expect(:cmd, fn "mix", ["dialyzer", "--plt"], opts -> {opts[:into], 2} end)

      capture_io(fn ->
        assert_raise Mix.Error, ~r/PLT build failed \(exit status 2\)/, fn -> Plt.run([]) end
      end)
    end
  end

  describe "run/1 without dialyxir" do
    test "says what is missing rather than running a build that cannot work" do
      stub(Tools, :available?, fn :dialyzer -> false end)
      reject(&System.cmd/3)

      capture_io(fn ->
        assert_raise Mix.Error, ~r/needs :dialyxir/, fn -> Plt.run([]) end
      end)
    end
  end
end
