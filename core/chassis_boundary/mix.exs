if bootstrap = System.get_env("MIX_WORKSPACE_OPS_BOOTSTRAP"), do: Code.require_file(bootstrap)

defmodule Chassis.Boundary.MixProject do
  use Mix.Project

  def project do
    [
      app: :chassis_boundary,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Ring 0 boundary protocol, envelopes, adapters, and registry"
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto, :public_key, :ssh]
    ]
  end

  defp deps do
    [
      workspace_dep({:ground_plane_contracts, "~> 0.1.0"}),
      {:chassis_secret_refs, path: "../../secrets/chassis_secret_refs"}
    ]
  end

  defp workspace_dep(committed) do
    if function_exported?(MixWorkspaceOpsBootstrap, :dep, 2),
      do: apply(MixWorkspaceOpsBootstrap, :dep, [committed, __DIR__]),
      else: committed
  end
end
