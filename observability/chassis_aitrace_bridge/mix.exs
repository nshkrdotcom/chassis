unless Code.ensure_loaded?(DependencySources) do
  Code.require_file("../../build_support/dependency_sources.exs", __DIR__)
end

defmodule Chassis.Aitrace.Bridge.MixProject do
  use Mix.Project

  @repo_root Path.expand("../..", __DIR__)

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
      DependencySources.dep(:aitrace, @repo_root),
      {:jason, "~> 1.4.5"}
    ]
  end
end
