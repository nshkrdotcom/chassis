defmodule Chassis.Host.Daemon.MixProject do
  use Mix.Project

  def project do
    [
      app: :chassis_host_daemon,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Host-resident daemon and Unix socket routing"
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
      {:chassis_policy_boundary, path: "../../core/chassis_policy_boundary"},
      {:jason, "~> 1.4.5"}
    ]
  end
end
