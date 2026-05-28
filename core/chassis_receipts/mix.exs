defmodule Chassis.Receipts.MixProject do
  use Mix.Project

  def project do
    [
      app: :chassis_receipts,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Spatial deployment, health, and rollback receipts schema and redaction"
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:chassis_contracts, [path: "../chassis_contracts"]}
    ]
  end
end
