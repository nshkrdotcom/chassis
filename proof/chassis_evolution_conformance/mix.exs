defmodule Chassis.Evolution.Conformance.MixProject do
  use Mix.Project

  def project do
    [
      app: :chassis_evolution_conformance,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Evolution conformance scenarios"
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto, :public_key, :ssh]
    ]
  end

  defp deps do
    [
      {:chassis_metrics, path: "../../observability/chassis_metrics"},
      {:jason, "~> 1.4.5"}
    ]
  end
end
