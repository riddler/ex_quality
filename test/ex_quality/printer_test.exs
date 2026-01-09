defmodule ExQuality.PrinterTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureIO

  alias ExQuality.Printer

  setup do
    # Start the printer for each test
    {:ok, _pid} = Printer.start_link()

    on_exit(fn ->
      # Ensure printer is stopped after each test
      # Catch exit in case process already stopped (race condition)
      try do
        if Process.whereis(ExQuality.Printer) do
          Printer.stop()
        end
      catch
        :exit, _ -> :ok
      end
    end)

    :ok
  end

  describe "print_result/1" do
    test "successfully prints success result" do
      result = %{
        name: "Format",
        status: :ok,
        summary: "No changes needed",
        duration_ms: 123,
        output: "",
        stats: %{}
      }

      capture_io(fn ->
        assert :ok = Printer.print_result(result)
      end)
    end

    test "successfully prints error result" do
      result = %{
        name: "Compile",
        status: :error,
        summary: "Compilation failed",
        duration_ms: 2500,
        output: "error output",
        stats: %{}
      }

      capture_io(fn ->
        assert :ok = Printer.print_result(result)
      end)
    end

    test "successfully prints skipped result" do
      result = %{
        name: "Dialyzer",
        status: :skipped,
        summary: "Skipped",
        duration_ms: 0,
        output: "",
        stats: %{}
      }

      capture_io(fn ->
        assert :ok = Printer.print_result(result)
      end)
    end

    test "handles various duration values" do
      capture_io(fn ->
        # Test milliseconds (< 1000ms)
        result_ms = %{
          name: "Fast",
          status: :ok,
          summary: "Done",
          duration_ms: 500,
          output: "",
          stats: %{}
        }

        assert :ok = Printer.print_result(result_ms)

        # Test seconds (>= 1000ms)
        result_s = %{
          name: "Slow",
          status: :ok,
          summary: "Done",
          duration_ms: 45_300,
          output: "",
          stats: %{}
        }

        assert :ok = Printer.print_result(result_s)

        # Test exactly 1000ms
        result_exact = %{
          name: "Exact",
          status: :ok,
          summary: "Done",
          duration_ms: 1000,
          output: "",
          stats: %{}
        }

        assert :ok = Printer.print_result(result_exact)

        # Test 0ms
        result_zero = %{
          name: "Instant",
          status: :ok,
          summary: "Done",
          duration_ms: 0,
          output: "",
          stats: %{}
        }

        assert :ok = Printer.print_result(result_zero)
      end)
    end

    test "handles concurrent prints without errors" do
      capture_io(fn ->
        # Create multiple results
        results =
          Enum.map(1..10, fn i ->
            %{
              name: "Stage #{i}",
              status: :ok,
              summary: "Done",
              duration_ms: 100 * i,
              output: "",
              stats: %{}
            }
          end)

        # Print them concurrently
        tasks =
          Enum.map(results, fn result ->
            Task.async(fn ->
              Printer.print_result(result)
            end)
          end)

        # Wait for all tasks and verify they all succeed
        results = Enum.map(tasks, &Task.await/1)
        assert Enum.all?(results, &(&1 == :ok))
      end)
    end

    test "handles all result fields correctly" do
      capture_io(fn ->
        result = %{
          name: "Complete Test",
          status: :ok,
          summary: "Test summary",
          duration_ms: 1234,
          output: "some output",
          stats: %{test_count: 42, passed: 40, failed: 2}
        }

        assert :ok = Printer.print_result(result)
      end)
    end
  end

  describe "print_message/1" do
    test "successfully prints a message" do
      capture_io(fn ->
        assert :ok = Printer.print_message("Hello, world!")
      end)
    end

    test "handles concurrent messages without errors" do
      capture_io(fn ->
        messages = Enum.map(1..10, &"Message #{&1}")

        tasks =
          Enum.map(messages, fn msg ->
            Task.async(fn ->
              Printer.print_message(msg)
            end)
          end)

        results = Enum.map(tasks, &Task.await/1)
        assert Enum.all?(results, &(&1 == :ok))
      end)
    end

    test "handles various message types" do
      capture_io(fn ->
        assert :ok = Printer.print_message("")
        assert :ok = Printer.print_message("Simple message")
        assert :ok = Printer.print_message("Message with\nmultiple lines")
        assert :ok = Printer.print_message("Message with special chars: ✓ ✗ ○")
      end)
    end
  end

  describe "start_link/1 and stop/0" do
    test "can be started and stopped multiple times" do
      # Stop the one from setup
      Printer.stop()

      # Start new one
      assert {:ok, pid} = Printer.start_link()
      assert is_pid(pid)
      assert Process.whereis(ExQuality.Printer) != nil

      # Stop it
      assert :ok = Printer.stop()
      Process.sleep(10)
      assert Process.whereis(ExQuality.Printer) == nil

      # Start again for cleanup
      {:ok, _pid} = Printer.start_link()
    end

    test "is registered with module name" do
      assert Process.whereis(ExQuality.Printer) != nil
    end
  end

  describe "concurrency and atomicity" do
    test "serializes output from concurrent calls" do
      capture_io(fn ->
        # Mix multiple result types concurrently
        results = [
          %{
            name: "Stage 1",
            status: :ok,
            summary: "OK",
            duration_ms: 100,
            output: "",
            stats: %{}
          },
          %{
            name: "Stage 2",
            status: :error,
            summary: "Failed",
            duration_ms: 200,
            output: "",
            stats: %{}
          },
          %{
            name: "Stage 3",
            status: :skipped,
            summary: "Skipped",
            duration_ms: 0,
            output: "",
            stats: %{}
          }
        ]

        # Run concurrently with both print_result and print_message
        tasks =
          Enum.flat_map(results, fn result ->
            [
              Task.async(fn -> Printer.print_result(result) end),
              Task.async(fn -> Printer.print_message("Message for #{result.name}") end)
            ]
          end)

        # All should complete successfully
        task_results = Enum.map(tasks, &Task.await/1)
        assert Enum.all?(task_results, &(&1 == :ok))
      end)
    end
  end
end
