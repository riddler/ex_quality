defmodule CredoIssues do
  # Missing @moduledoc

  def add(a, b) do
    # TODO: optimize this later
    a + b
  end

  def complex_function(x) do
    if x > 0 do
      if x > 10 do
        if x > 100 do
          :very_large
        else
          :large
        end
      else
        :small
      end
    else
      :negative
    end
  end
end
