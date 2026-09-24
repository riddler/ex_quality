defmodule DocLinksFunctionDocs.MixProject do
  use Mix.Project

  def project do
    [
      app: :doc_links_function_docs,
      version: "0.1.0",
      elixir: "~> 1.14",
      deps: deps(),
      package: [files: ~w(lib docs mix.exs README.md)],
      docs: &docs/0
    ]
  end

  defp deps do
    [
      {:ex_quality, path: "../../..", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40", only: :dev, runtime: false}
    ]
  end

  defp docs do
    [extras: ["README.md", "docs/parcels.md"]]
  end
end
