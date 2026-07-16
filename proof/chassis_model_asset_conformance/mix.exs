defmodule Chassis.Model.Asset.Conformance.MixProject do
  use Mix.Project

  def project do
    [
      app: :chassis_model_asset_conformance,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Model asset conformance scenarios"
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto, :public_key, :ssh]
    ]
  end

  defp deps do
    [
      {:chassis_hardware_guard, path: "../../model/chassis_hardware_guard"},
      {:chassis_tensor_reload, path: "../../model/chassis_tensor_reload"},
      {:chassis_weight_materializer, path: "../../model/chassis_weight_materializer"},
      {:jason, "~> 1.4.5"}
    ]
  end
end
