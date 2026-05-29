defmodule Chassis.Inventory.MixProject do
  use Mix.Project

  def project do
    [
      app: :chassis_inventory,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Host, capacity, GPU, and discovery inventory"
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto, :public_key, :ssh]
    ]
  end

  defp deps, do: []
end
