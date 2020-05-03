defmodule Shodan.MixProject do
  use Mix.Project

  def project do
    [
      app: :shodan,
      version: "0.1.0",
      elixir: "~> 1.10",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      mod: {Shodan.Application, []},
      extra_applications: [
        :logger,
        :hackney,
        :runtime_tools,
        :observer,
        :wx,
      ]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:tesla, "~> 1.3.0"},
      {:poison, "~> 3.1"},
      {:flow, "~> 1.0"},
      {:meeseeks, "~> 0.15.0"},
      {:meeseeks_html5ever, "~> 0.12.1"},
      {:dialyxir, "~> 1.0", only: [:dev], runtime: false},
      {:erlsom, "~> 1.5"},
      {:hackney, "~> 1.13"},
      {:broadway, "~> 0.6.0"},
      {:ecto_sql, "~> 3.0"},
      {:postgrex, ">= 0.0.0"},
      {:logger_file_backend, "~> 0.0.11"},
      {:distillery, "~> 2.0"},
      {:inet_cidr, "~> 1.0"},
    ]
  end
end
