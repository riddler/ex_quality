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

  describe "new/1 with :on_line" do
    test "calls the handler with each complete line as it arrives" do
      test_pid = self()
      collector = OutputCollector.new(on_line: &send(test_pid, {:line, &1}))

      {_output, 0} = System.cmd("printf", ["line1\nline2\n"], into: collector)

      assert_received {:line, "line1"}
      assert_received {:line, "line2"}
    end

    test "reassembles a line split across chunks" do
      test_pid = self()
      collector = OutputCollector.new(on_line: &send(test_pid, {:line, &1}))

      _collected = Enum.into(["Adding 12 mod", "ules to a.plt\nnext\n"], collector)

      assert_received {:line, "Adding 12 modules to a.plt"}
      assert_received {:line, "next"}
      assert OutputCollector.get_output(collector) == "Adding 12 modules to a.plt\nnext\n"
    end

    test "holds back a line the command has not finished writing" do
      test_pid = self()
      collector = OutputCollector.new(on_line: &send(test_pid, {:line, &1}))

      _collected = Enum.into(["partial"], collector)

      refute_received {:line, _line}
      assert OutputCollector.get_output(collector) == "partial"
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
