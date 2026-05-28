defmodule Chassis.Core.MixProject do
  use Mix.Project

  def project do
    [
      app: :chassis_core,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Chassis core orchestration state and router engine"
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:chassis_contracts, [path: "../chassis_contracts"]},
      {:chassis_receipts, [path: "../chassis_receipts"]}
    ]
  end
end
