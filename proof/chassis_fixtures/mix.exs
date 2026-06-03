defmodule Chassis.Fixtures.MixProject do
  use Mix.Project

  def project do
    [
      app: :chassis_fixtures,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Canonical topology fixtures"
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto, :public_key, :ssh]
    ]
  end

  defp deps do
    [
      {:chassis_inventory, path: "../../core/chassis_inventory"},
      {:chassis_stack, path: "../../core/chassis_stack"},
      {:chassis_stack_manager, path: "../../manager/chassis_stack_manager"}
    ]
  end
end
