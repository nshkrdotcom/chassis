defmodule Chassis.CLI.MixProject do
  use Mix.Project

  def project do
    [
      app: :chassis_cli,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "CLI subcommands router and interface layer"
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:chassis_stack_manager, [path: "../chassis_stack_manager"]}
    ]
  end
end
