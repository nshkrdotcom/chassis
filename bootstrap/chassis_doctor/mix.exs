defmodule Chassis.Doctor.MixProject do
  use Mix.Project

  def project do
    [
      app: :chassis_doctor,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Node, host, and mesh diagnostics"
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps, do: []
end
