if bootstrap = System.get_env("MIX_WORKSPACE_OPS_BOOTSTRAP"), do: Code.require_file(bootstrap)

defmodule Chassis.Stack.Manager.MixProject do
  use Mix.Project

  def project do
    [
      app: :chassis_stack_manager,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Deployment transactions and rollback orchestration"
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto, :public_key, :ssh]
    ]
  end

  defp deps do
    [
      {:chassis_inventory, path: "../../core/chassis_inventory"},
      {:chassis_receipts, path: "../../core/chassis_receipts"},
      {:chassis_releases, path: "../../core/chassis_releases"},
      {:chassis_stack, path: "../../core/chassis_stack"},
      {:chassis_tenant, path: "../../core/chassis_tenant"},
      workspace_dep({:ground_plane_contracts, "~> 0.1.0"})
    ]
  end

  defp workspace_dep(committed) do
    if function_exported?(MixWorkspaceOpsBootstrap, :dep, 2),
      do: apply(MixWorkspaceOpsBootstrap, :dep, [committed, __DIR__]),
      else: committed
  end
end
