defmodule ExQuality.Stages.Compile do
  @moduledoc """
  Compiles the project in both dev and test environments.

  Runs `mix compile --warnings-as-errors` in parallel for both
  MIX_ENV=dev and MIX_ENV=test. Both compilations must succeed
  for the stage to pass.

  - dev environment is needed for credo, dialyzer, doctor, and gettext
  - test environment is needed for running tests
  """

  @doc """
  Runs the compile stage.

  Compiles both dev and test environments in parallel. If either
  compilation fails, the entire stage fails with the error output.
  """
  @spec run(keyword()) :: ExQuality.Stage.result()
  def run(config) do
    start_time = System.monotonic_time(:millisecond)

    warnings_as_errors =
      config
      |> Keyword.get(:compile, [])
      |> Keyword.get(:warnings_as_errors, true)

    # Run both compilations in parallel
    dev_task = Task.async(fn -> compile_env("dev", warnings_as_errors) end)
    test_task = Task.async(fn -> compile_env("test", warnings_as_errors) end)

    dev_result = Task.await(dev_task, :infinity)
    test_result = Task.await(test_task, :infinity)

    duration_ms = System.monotonic_time(:millisecond) - start_time

    case {dev_result, test_result} do
      {{:ok, dev_output}, {:ok, test_output}} ->
        warnings_note = if warnings_as_errors, do: " (warnings as errors)", else: ""

        %{
          name: "Compile",
          status: :ok,
          output: format_success_output(dev_output, test_output),
          stats: %{},
          summary: "dev + test compiled#{warnings_note}",
          duration_ms: duration_ms
        }

      {{:error, output}, _} ->
        %{
          name: "Compile (dev)",
          status: :error,
          output: output,
          stats: %{},
          summary: "dev compilation failed",
          duration_ms: duration_ms
        }

      {_, {:error, output}} ->
        %{
          name: "Compile (test)",
          status: :error,
          output: output,
          stats: %{},
          summary: "test compilation failed",
          duration_ms: duration_ms
        }
    end
  end

  defp compile_env(env, warnings_as_errors) do
    args =
      if warnings_as_errors do
        ["compile", "--warnings-as-errors"]
      else
        ["compile"]
      end

    {output, exit_code} =
      System.cmd("mix", args,
        env: [{"MIX_ENV", env}],
        stderr_to_stdout: true
      )

    if exit_code == 0, do: {:ok, output}, else: {:error, output}
  end

  defp format_success_output(dev_output, test_output) do
    # Only show output if there's something interesting (not just "Compiled in X.Xs")
    dev_lines = String.split(dev_output, "\n") |> Enum.reject(&is_boring_line?/1)
    test_lines = String.split(test_output, "\n") |> Enum.reject(&is_boring_line?/1)

    parts = []

    parts =
      if dev_lines != [] do
        ["=== dev ===\n#{Enum.join(dev_lines, "\n")}" | parts]
      else
        parts
      end

    parts =
      if test_lines != [] do
        ["=== test ===\n#{Enum.join(test_lines, "\n")}" | parts]
      else
        parts
      end

    if parts == [] do
      ""
    else
      Enum.reverse(parts) |> Enum.join("\n\n")
    end
  end

  defp is_boring_line?(line) do
    trimmed = String.trim(line)

    trimmed == "" or
      String.starts_with?(trimmed, "Compiling ") or
      String.starts_with?(trimmed, "Compiled in ") or
      String.starts_with?(trimmed, "Generated ")
  end
end
