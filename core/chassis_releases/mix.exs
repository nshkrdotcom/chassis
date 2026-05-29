defmodule Chassis.Releases.MixProject do
  use Mix.Project

  def project do
    [
      app: :chassis_releases,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Release bundles, app registry, and approved mounts"
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto, :public_key, :ssh]
    ]
  end

  defp deps, do: []
end
