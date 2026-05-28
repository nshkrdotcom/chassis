defmodule Chassis.StackManager.MixProject do
  use Mix.Project

  def project do
    [
      app: :chassis_stack_manager,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Core CLI stack management workflow executor engine"
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:chassis_contracts, [path: "../../core/chassis_contracts"]},
      {:chassis_core, [path: "../../core/chassis_core"]},
      {:chassis_stack, [path: "../../core/chassis_stack"]},
      {:chassis_releases, [path: "../../core/chassis_releases"]},
      {:chassis_inventory, [path: "../../core/chassis_inventory"]},
      {:chassis_receipts, [path: "../../core/chassis_receipts"]},
      {:chassis_bootstrap, [path: "../../bootstrap/chassis_bootstrap"]},
      {:chassis_installer, [path: "../../bootstrap/chassis_installer"]},
      {:chassis_doctor, [path: "../../bootstrap/chassis_doctor"]}
    ]
  end
end
