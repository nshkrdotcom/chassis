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
      {:ground_plane_contracts, path: "../../../ground_plane/core/ground_plane_contracts"}
    ]
  end
end
