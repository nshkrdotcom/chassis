defmodule Chassis.Doctor.MixProject do
  use Mix.Project

  def project do
    [
      app: :chassis_doctor,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Preflight diagnostic checkers for CPU, memory, Erlang, systemd, SSH"
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:chassis_contracts, [path: "../../core/chassis_contracts"]},
      {:chassis_inventory, [path: "../../core/chassis_inventory"]}
    ]
  end
end
