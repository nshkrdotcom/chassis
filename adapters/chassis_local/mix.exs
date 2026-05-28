defmodule Chassis.Local.MixProject do
  use Mix.Project

  def project do
    [
      app: :chassis_local,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Direct OS subprocess command execution adapter"
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:chassis_contracts, [path: "../../core/chassis_contracts"]}
    ]
  end
end
