defmodule Chassis.Evolution.Receipts.MixProject do
  use Mix.Project

  def project do
    [
      app: :chassis_evolution_receipts,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Evolution receipt records"
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:chassis_evolution_contracts, path: "../chassis_evolution_contracts"}
    ]
  end
end
