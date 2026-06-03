defmodule Chassis.Conformance.MixProject do
  use Mix.Project

  def project do
    [
      app: :chassis_conformance,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Baseline Chassis conformance harness"
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
      {:chassis_fixtures, path: "../chassis_fixtures"},
      {:chassis_receipts, path: "../../core/chassis_receipts"},
      {:chassis_releases, path: "../../core/chassis_releases"},
      {:chassis_stack_manager, path: "../../manager/chassis_stack_manager"},
      {:chassis_tenant, path: "../../core/chassis_tenant"},
      {:jason, "~> 1.4"}
    ]
  end
end
