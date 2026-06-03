defmodule Chassis.Health.Probe.MixProject do
  use Mix.Project

  def project do
    [
      app: :chassis_health_probe,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Health probe and rollback window"
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto, :public_key, :ssh]
    ]
  end

  defp deps do
    [
      {:chassis_evolution_contracts, path: "../../evolution/chassis_evolution_contracts"},
      {:chassis_mesh, path: "../../core/chassis_mesh"},
      {:chassis_aitrace_bridge, path: "../../observability/chassis_aitrace_bridge"},
      {:chassis_metrics, path: "../../observability/chassis_metrics"},
      {:chassis_swap_supervisor, path: "../chassis_swap_supervisor"},
      {:jason, "~> 1.4"}
    ]
  end
end
