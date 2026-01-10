defmodule ExQuality.OutputCollectorTest do
  use ExUnit.Case, async: true

  alias ExQuality.OutputCollector

  describe "new/0" do
    test "creates a new collector" do
      collector = OutputCollector.new()
      assert %OutputCollector{pid: pid} = collector
      assert is_pid(pid)
      assert Process.alive?(pid)
    end
  end

  describe "Collectable implementation" do
    test "collects output from System.cmd" do
      collector = OutputCollector.new()
      {_output, 0} = System.cmd("echo", ["hello"], into: collector)
      output = OutputCollector.get_output(collector)
      assert output == "hello\n"
    end

    test "collects multiple lines" do
      collector = OutputCollector.new()
      {_output, 0} = System.cmd("echo", ["-e", "line1\\nline2\\nline3"], into: collector)
      output = OutputCollector.get_output(collector)
      assert output =~ "line1"
      assert output =~ "line2"
      assert output =~ "line3"
    end

    test "handles empty output" do
      collector = OutputCollector.new()
      {_output, 0} = System.cmd("true", [], into: collector)
      output = OutputCollector.get_output(collector)
      assert output == ""
    end
  end

  describe "get_output/1" do
    test "stops the agent after retrieving output" do
      collector = OutputCollector.new()
      pid = collector.pid
      {_output, 0} = System.cmd("echo", ["test"], into: collector)

      assert Process.alive?(pid)
      _output = OutputCollector.get_output(collector)

      # Give the agent a moment to stop
      Process.sleep(10)
      refute Process.alive?(pid)
    end
  end
end
