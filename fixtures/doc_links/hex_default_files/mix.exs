defmodule DocLinksHexDefault.MixProject do
  use Mix.Project

  def project do
    [
      app: :doc_links_hex_default,
      version: "0.1.0",
      elixir: "~> 1.14",
      deps: deps(),
      package: [licenses: ["MIT"]],
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
    [extras: ["docs/holds.md"]]
  end
end
