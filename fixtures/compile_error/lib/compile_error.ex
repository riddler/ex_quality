defmodule CompileError do
  @moduledoc """
  A module with compilation errors.
  """

  def broken_function do
    undefined_function()
  end

  def another_broken do
    UndefinedModule.call()
  end
end
