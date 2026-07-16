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
      extra_applications: [:logger, :crypto]
    ]
  end

  defp deps do
    [
      {:jason, "~> 1.4.5"}
    ]
  end
end
