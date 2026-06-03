defmodule Chassis.Policy.Boundary.MixProject do
  use Mix.Project

  def project do
    [
      app: :chassis_policy_boundary,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Citadel authority boundary integration"
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto, :public_key, :ssh]
    ]
  end

  defp deps do
    [
      {:chassis_boundary, path: "../chassis_boundary"},
      {:chassis_evolution_receipts, path: "../../evolution/chassis_evolution_receipts"},
      {:citadel_governance, path: "../../../citadel/core/citadel_governance"},
      {:citadel_authority_contract, path: "../../../citadel/core/authority_contract"}
    ]
  end
end
