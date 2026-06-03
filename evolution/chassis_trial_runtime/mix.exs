defmodule Chassis.Trial.Runtime.MixProject do
  use Mix.Project

  def project do
    [
      app: :chassis_trial_runtime,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Trial runtime providers"
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
      {:chassis_trial_supervisor, path: "../../host/chassis_trial_supervisor"},
      {:jason, "~> 1.4"}
    ]
  end
end
