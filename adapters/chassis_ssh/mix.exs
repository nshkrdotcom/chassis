defmodule Chassis.Adapter.SSH.MixProject do
  use Mix.Project
  def project, do: [app: :chassis_ssh, version: "0.1.0", elixir: "~> 1.19", deps: deps()]
  def application, do: [extra_applications: [:logger, :crypto, :public_key, :ssh]]
  defp deps, do: [{:chassis_contracts, path: "../../core/chassis_contracts"}]
end
