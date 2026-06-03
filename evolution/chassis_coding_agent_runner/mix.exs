defmodule Chassis.Coding.Agent.Runner.MixProject do
  use Mix.Project

  def project do
    [
      app: :chassis_coding_agent_runner,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "External coding-agent runner"
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
      {:chassis_evolution_receipts, path: "../chassis_evolution_receipts"},
      {:chassis_secret_refs, path: "../../secrets/chassis_secret_refs"}
    ]
  end
end
