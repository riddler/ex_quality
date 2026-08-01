defmodule NativeCoverage do
  @moduledoc """
  A module whose tests cover one function and leave the rest alone.
  """

  @doc """
  Adds two numbers together.
  """
  @spec add(number(), number()) :: number()
  def add(a, b) do
    a + b
  end

  @doc """
  Subtracts one number from another.
  """
  @spec subtract(number(), number()) :: number()
  def subtract(a, b) do
    a - b
  end

  @doc """
  Multiplies two numbers.
  """
  @spec multiply(number(), number()) :: number()
  def multiply(a, b) do
    a * b
  end

  @doc """
  Divides one number by another.
  """
  @spec divide(number(), number()) :: float()
  def divide(a, b) do
    a / b
  end
end
