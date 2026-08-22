defmodule ExQuality.Stages.FormatSkipTest do
  # Not async: the stage looks for `.formatter.exs` where the command would
  # run, so the test has to change the working directory, which is global.
  use ExUnit.Case, async: false

  alias ExQuality.Stages.Format

  @tag :tmp_dir
  test "skips rather than failing a run over a missing .formatter.exs", %{tmp_dir: tmp_dir} do
    result = File.cd!(tmp_dir, fn -> Format.run([]) end)

    assert result.status == :skipped
    assert result.summary == "no .formatter.exs"
  end

  @tag :tmp_dir
  test "check mode skips over a missing .formatter.exs the same way", %{tmp_dir: tmp_dir} do
    # A project that has never used the formatter has nothing to check.
    result = File.cd!(tmp_dir, fn -> Format.run(format: [check: true]) end)

    assert result.status == :skipped
    assert result.summary == "no .formatter.exs"
  end

  @tag :tmp_dir
  test "runs when the project has one", %{tmp_dir: tmp_dir} do
    File.write!(Path.join(tmp_dir, ".formatter.exs"), "[inputs: []]")

    result = File.cd!(tmp_dir, fn -> Format.run([]) end)

    assert result.status == :ok
    assert result.summary == "No changes needed"
  end
end
