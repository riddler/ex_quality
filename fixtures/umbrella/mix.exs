defmodule Umbrella.MixProject do
  use Mix.Project

  def project do
    [
      apps_path: "apps",
      version: "0.1.0",
      elixir: "~> 1.14",
      deps: deps()
    ]
  end

  # The root declares no quality tools of its own. Credo lives in apps/core,
  # which is what tool auto-detection has to find.
  defp deps do
    [
      {:ex_quality, path: "../../..", only: [:dev, :test], runtime: false}
    ]
  end
end
