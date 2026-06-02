defmodule Chassis.Environments.MixProject do
  use Mix.Project

  def project do
    [
      app: :chassis_environments,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Compile-time embedded provisioning profiles + resolver catalog"
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [{:jason, "~> 1.4"}]
  end
end
