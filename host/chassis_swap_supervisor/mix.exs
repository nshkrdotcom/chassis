defmodule Chassis.Swap.Supervisor.MixProject do
  use Mix.Project

  def project do
    [
      app: :chassis_swap_supervisor,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "State-preserving swap supervisor"
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
      {:chassis_releases, path: "../../core/chassis_releases"},
      {:jason, "~> 1.4.5"}
    ]
  end
end
