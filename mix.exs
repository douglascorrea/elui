defmodule Elui.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/douglascorrea/elui"
  @homepage_url "https://elui.sh"

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
      homepage_url: @homepage_url,
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
      maintainers: ["Douglas Correa"],
      links: %{
        "Changelog" => "#{@source_url}/blob/master/CHANGELOG.md",
        "GitHub" => @source_url,
        "Website" => @homepage_url
      },
      files:
        ~w(lib examples mix.exs README.md LICENSE CHANGELOG.md CONTRIBUTING.md SECURITY.md CODE_OF_CONDUCT.md SUPPORT.md)
    ]
  end

  defp docs do
    [
      main: "Elui",
      source_ref: "v#{@version}",
      source_url: @source_url,
      extras: [
        "README.md",
        "CHANGELOG.md",
        "CONTRIBUTING.md",
        "SECURITY.md",
        "CODE_OF_CONDUCT.md",
        "SUPPORT.md",
        "LICENSE"
      ]
    ]
  end
end
