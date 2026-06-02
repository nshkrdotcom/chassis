defmodule Chassis.Bootstrap.MixProject do
  use Mix.Project

  def project do
    [
      app: :chassis_bootstrap,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "SSH-driven host bootstrap state machine"
    ]
  end

  def application do
    [extra_applications: [:logger, :crypto, :public_key, :ssh]]
  end

  defp deps do
    [
      {:chassis_contracts, path: "../../core/chassis_contracts"},
      {:chassis_receipts, path: "../../core/chassis_receipts"}
    ]
  end
end
