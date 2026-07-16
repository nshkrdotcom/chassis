defmodule Chassis.Stacklab.Bridge.MixProject do
  use Mix.Project

  def project do
    [
      app: :chassis_stacklab_bridge,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "StackLab proof bridge"
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto, :public_key, :ssh]
    ]
  end

  defp deps do
    [
      {:chassis_boundary, path: "../../core/chassis_boundary"},
      {:chassis_conformance, path: "../chassis_conformance"},
      {:jason, "~> 1.4.5"}
    ]
  end
end
