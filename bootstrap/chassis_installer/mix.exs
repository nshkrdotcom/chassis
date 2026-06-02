defmodule Chassis.Installer.MixProject do
  use Mix.Project

  def project do
    [
      app: :chassis_installer,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Target-host release bundle installer"
    ]
  end

  def application do
    [extra_applications: [:logger, :crypto]]
  end

  defp deps do
    [{:chassis_contracts, path: "../../core/chassis_contracts"}]
  end
end
