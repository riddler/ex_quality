defmodule DocLinksClean.MixProject do
  use Mix.Project

  def project do
    [
      app: :doc_links_clean,
      version: "0.1.0",
      elixir: "~> 1.14",
      deps: deps(),
      package: [files: ~w(lib docs mix.exs README.md assets/branch.svg)],
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
    [
      assets: %{"assets" => "assets"},
      extras: [
        "README.md",
        "docs/holds.md",
        {"docs/loans.md", [title: "Loans"]},
        "docs/branches.md": [filename: "branch-guide"]
      ]
    ]
  end
end
