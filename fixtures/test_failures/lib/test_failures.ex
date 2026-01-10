defmodule TestFailures do
  @moduledoc """
  A module with correct code but failing tests.
  """

  @doc """
  Adds two numbers.
  """
  def add(a, b) do
    a + b
  end

  @doc """
  Multiplies two numbers.
  """
  def multiply(a, b) do
    a * b
  end
end
