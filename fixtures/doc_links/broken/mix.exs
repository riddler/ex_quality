defmodule DocLinksBroken.MixProject do
  use Mix.Project

  def project do
    [
      app: :doc_links_broken,
      version: "0.1.0",
      elixir: "~> 1.14",
      deps: deps(),
      package: [files: ~w(lib mix.exs README.md)],
      docs: docs()
    ]
  end

  defp deps do
    [
      {:ex_quality, path: "../../..", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40", only: :dev, runtime: false}
    ]
  end

  defp docs do
    [extras: ["README.md", "docs/holds.md"]]
  end
end
