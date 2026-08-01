defmodule Web do
  @moduledoc """
  A child app with nothing for credo to report.
  """

  @doc "Adds one to a number."
  def increment(number), do: Core.add(number, 1)
end
