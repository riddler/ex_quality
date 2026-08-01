defmodule ExQuality.MixProject do
  use Mix.Project

  @version "0.8.0"
  @source_url "https://github.com/riddler/ex_quality"

  def project do
    [
      app: :ex_quality,
      version: @version,
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      docs: docs(),
      name: "ExQuality",
      source_url: @source_url,
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test
      ],
      dialyzer: [
        plt_add_apps: [:mix, :jason],
        flags: [:unmatched_returns, :error_handling, :underspecs]
      ]
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:doctor, "~> 0.23", only: :dev},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:excoveralls, "~> 0.18", only: :test},
      {:jason, "~> 1.4"},
      {:mimic, "~> 1.7", only: :test},
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false}
    ]
  end

  defp description do
    "Elixir code quality checker. Runs format, compile, Credo, Dialyzer, " <>
      "coverage, Sobelow and mix_audit in parallel from one mix task, and " <>
      "reports findings with file:line plus a JSON report for CI, scripts " <>
      "and AI coding agents. Umbrella-aware."
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      # `assets` is deliberately absent: HexDocs is built from the checkout at
      # publish time, so the mark reaches the docs without every project that
      # depends on this one downloading it.
      files: ~w(lib docs .formatter.exs mix.exs README.md LICENSE CHANGELOG.md usage-rules.md)
    ]
  end

  defp docs do
    [
      main: "readme",
      logo: "assets/ex_quality.svg",
      favicon: "assets/favicon.png",
      assets: %{"assets" => "assets"},
      extras: [
        "README.md",
        "docs/configuration.md",
        "docs/stages.md",
        "docs/reports.md",
        "docs/umbrella.md",
        "docs/ci.md",
        "usage-rules.md",
        "CHANGELOG.md"
      ],
      groups_for_extras: [
        Guides: Path.wildcard("docs/*.md")
      ]
    ]
  end
end
