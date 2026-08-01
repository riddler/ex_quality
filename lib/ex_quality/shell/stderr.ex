defmodule ExQuality.Shell.Stderr do
  @moduledoc """
  A `Mix.Shell` that writes informational output to stderr.

  `mix quality --format json` puts the machine-readable report on stdout, which
  only works if nothing else does. Installing this shell for the run moves the
  progress lines out of the way without every call site having to know which
  mode it is in.

  Errors already go to stderr under `Mix.Shell.IO`, and prompts are left alone,
  so only `info/1` differs.
  """

  @behaviour Mix.Shell

  @impl Mix.Shell
  def info(message), do: IO.puts(:stderr, IO.ANSI.format(message))

  @impl Mix.Shell
  defdelegate error(message), to: Mix.Shell.IO

  @impl Mix.Shell
  defdelegate print_app(), to: Mix.Shell.IO

  @impl Mix.Shell
  defdelegate prompt(message), to: Mix.Shell.IO

  @impl Mix.Shell
  defdelegate yes?(message), to: Mix.Shell.IO

  @impl Mix.Shell
  defdelegate yes?(message, options), to: Mix.Shell.IO

  @impl Mix.Shell
  defdelegate cmd(command), to: Mix.Shell.IO

  @impl Mix.Shell
  defdelegate cmd(command, options), to: Mix.Shell.IO
end
