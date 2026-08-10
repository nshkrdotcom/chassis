unless Code.ensure_loaded?(DependencySources) do
  Code.require_file("../../build_support/dependency_sources.exs", __DIR__)
end

defmodule Chassis.Boundary.MixProject do
  use Mix.Project

  @repo_root Path.expand("../..", __DIR__)

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
      DependencySources.dep(:ground_plane_contracts, @repo_root),
      {:chassis_secret_refs, path: "../../secrets/chassis_secret_refs"}
    ]
  end
end
