unless Code.ensure_loaded?(DependencySources) do
  Code.require_file("../../build_support/dependency_sources.exs", __DIR__)
end

defmodule Chassis.Policy.Boundary.MixProject do
  use Mix.Project

  @repo_root Path.expand("../..", __DIR__)

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
      DependencySources.dep(:citadel_governance, @repo_root),
      DependencySources.dep(:citadel_authority_contract, @repo_root)
    ]
  end
end
