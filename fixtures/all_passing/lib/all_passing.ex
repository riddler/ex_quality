defmodule AllPassing do
  @moduledoc """
  A simple module that passes all quality checks.
  """

  @doc """
  Adds two numbers together.
  """
  @spec add(number(), number()) :: number()
  def add(a, b) do
    a + b
  end
end
