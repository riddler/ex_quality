defmodule NativeCoverage.MixProject do
  use Mix.Project

  def project do
    [
      app: :native_coverage,
      version: "0.1.0",
      elixir: "~> 1.14",
      # No excoveralls: coverage is Elixir's own, and the threshold lives where
      # `mix test --cover` reads it from.
      test_coverage: [summary: [threshold: 90]],
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
