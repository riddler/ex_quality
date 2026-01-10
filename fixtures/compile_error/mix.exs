defmodule CompileError.MixProject do
  use Mix.Project

  def project do
    [
      app: :compile_error,
      version: "0.1.0",
      elixir: "~> 1.14",
      deps: deps()
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      {:ex_quality, path: "../../..", only: [:dev, :test], runtime: false}
    ]
  end
end
