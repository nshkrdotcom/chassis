defmodule Chassis.Adapter.Systemd.MixProject do
  use Mix.Project
  def project, do: [app: :chassis_systemd, version: "0.1.0", elixir: "~> 1.19", deps: deps()]
  def application, do: [extra_applications: [:logger]]
  defp deps, do: [{:chassis_contracts, path: "../../core/chassis_contracts"}]
end
