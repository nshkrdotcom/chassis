defmodule Chassis.Metrics.MixProject do
  use Mix.Project

  def project do
    [
      app: :chassis_metrics,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Operational metrics and health signal bridge"
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto, :telemetry]
    ]
  end

  defp deps do
    [
      {:chassis_contracts, path: "../../core/chassis_contracts"},
      {:jason, "~> 1.4"},
      {:telemetry, "~> 1.0"}
    ]
  end
end
