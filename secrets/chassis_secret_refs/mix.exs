defmodule Chassis.Secret.Refs.MixProject do
  use Mix.Project

  def project do
    [
      app: :chassis_secret_refs,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Secret refs, leases, and materializer behaviour"
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto, :public_key, :ssh]
    ]
  end

  defp deps, do: []
end
