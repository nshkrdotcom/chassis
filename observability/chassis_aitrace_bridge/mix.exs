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
      {:aitrace, path: "../../../AITrace"},
      {:jason, "~> 1.4"}
    ]
  end
end
