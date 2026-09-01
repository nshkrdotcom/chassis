if bootstrap = System.get_env("MIX_WORKSPACE_OPS_BOOTSTRAP"), do: Code.require_file(bootstrap)

defmodule Chassis.Aitrace.Bridge.MixProject do
  use Mix.Project

  def project do
    [
      app: :chassis_aitrace_bridge,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "AITrace span bridge"
    ]
  end

  def application do
    [
      mod: {Chassis.AITrace.Application, []},
      extra_applications: [:logger, :crypto],
      env: [
        runtime_env: Mix.env(),
        exporters: [{AITrace.Exporter.File, directory: "/tmp/chassis_aitrace"}]
      ]
    ]
  end

  defp deps do
    [
      workspace_dep({:aitrace, "~> 0.1.0"}),
      {:jason, "~> 1.4.5"}
    ]
  end

  defp workspace_dep(committed) do
    if function_exported?(MixWorkspaceOpsBootstrap, :dep, 2),
      do: apply(MixWorkspaceOpsBootstrap, :dep, [committed, __DIR__]),
      else: committed
  end
end
