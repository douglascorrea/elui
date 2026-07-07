defmodule Elui.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/douglascorrea/elui"

  def project do
    [
      app: :elui,
      version: @version,
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "A terminal user interface (TUI) library for Elixir, inspired by ratatui",
      package: package(),
      docs: docs(),
      name: "Elui",
      source_url: @source_url
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib examples mix.exs README.md)
    ]
  end

  defp docs do
    [
      main: "Elui",
      extras: ["README.md"]
    ]
  end
end
