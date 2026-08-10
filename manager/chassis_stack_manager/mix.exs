unless Code.ensure_loaded?(DependencySources) do
  Code.require_file("../../build_support/dependency_sources.exs", __DIR__)
end

defmodule Chassis.Stack.Manager.MixProject do
  use Mix.Project

  @repo_root Path.expand("../..", __DIR__)

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
      DependencySources.dep(:ground_plane_contracts, @repo_root)
    ]
  end
end
