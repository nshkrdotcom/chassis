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

  defp deps, do: []
end
