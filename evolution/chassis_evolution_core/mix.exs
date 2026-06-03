defmodule Chassis.Evolution.Core.MixProject do
  use Mix.Project

  def project do
    [
      app: :chassis_evolution_core,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Evolution lifecycle GenServer"
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:chassis_evolution_contracts, path: "../chassis_evolution_contracts"},
      {:jason, "~> 1.4"}
    ]
  end
end
