defmodule Chassis.Cli.MixProject do
  use Mix.Project

  def project do
    [
      app: :chassis_cli,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "CLI subcommand router",
      escript: [main_module: Chassis.CLI, name: "chassis"],
      releases: releases()
    ]
  end

  def application do
    [
      mod: {Chassis.CLI.Application, []},
      extra_applications: [:logger, :crypto, :public_key, :ssh]
    ]
  end

  defp deps do
    [
      {:bunt, "~> 1.0"},
      {:burrito, "~> 1.5", runtime: false},
      {:chassis_bootstrap, path: "../../bootstrap/chassis_bootstrap"},
      {:chassis_doctor, path: "../../bootstrap/chassis_doctor"},
      {:chassis_environments, path: "../../core/chassis_environments"},
      {:chassis_inventory, path: "../../core/chassis_inventory"},
      {:chassis_mezzanine_bridge, path: "../../governance/chassis_mezzanine_bridge"},
      {:chassis_secret_sops, path: "../../secrets/chassis_secret_sops"},
      {:chassis_stack_manager, path: "../chassis_stack_manager"},
      {:jason, "~> 1.4"}
    ]
  end

  defp releases do
    [
      chassis: [
        steps: [:assemble, &Burrito.wrap/1],
        burrito: [
          targets: [
            linux_x86_64: [os: :linux, cpu: :x86_64],
            linux_aarch64: [os: :linux, cpu: :aarch64],
            macos_x86_64: [os: :darwin, cpu: :x86_64],
            macos_arm64: [os: :darwin, cpu: :aarch64]
          ]
        ]
      ]
    ]
  end
end
