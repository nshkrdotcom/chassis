if bootstrap = System.get_env("MIX_WORKSPACE_OPS_BOOTSTRAP"), do: Code.require_file(bootstrap)

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
      workspace_dep({:citadel_governance, "~> 0.1.0"}),
      workspace_dep({:citadel_authority_contract, "~> 0.1.0"})
    ]
  end

  defp workspace_dep(committed) do
    if function_exported?(MixWorkspaceOpsBootstrap, :dep, 2),
      do: apply(MixWorkspaceOpsBootstrap, :dep, [committed, __DIR__]),
      else: committed
  end
end
