unless Code.ensure_loaded?(DependencySources) do
  Code.require_file("build_support/dependency_sources.exs", __DIR__)
end

defmodule Chassis.Workspace.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/nshkrdotcom/chassis"

  def project do
    [
      app: :chassis_workspace,
      version: @version,
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      blitz_workspace: blitz_workspace(),
      dialyzer: [plt_add_apps: [:mix]],
      docs: docs(),
      source_url: @source_url,
      name: "Chassis Workspace",
      description: "Tooling root for the Chassis non-umbrella monorepo",
      escript: [main_module: Chassis.CLI, name: "chassis"],
      elixirc_paths: ["lib"]
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto, :public_key, :ssh]
    ]
  end

  defp deps do
    [
      {:blitz, "~> 0.3.0", runtime: false},
      {:chassis_evolution_conformance, path: "proof/chassis_evolution_conformance"},
      {:chassis_hardware_guard, path: "model/chassis_hardware_guard"},
      {:chassis_weight_materializer, path: "model/chassis_weight_materializer"},
      {:weld, "~> 0.8.2", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40.1", only: :dev, runtime: false}
    ]
  end

  def cli do
    [
      preferred_envs: [
        credo: :test,
        dialyzer: :test,
        ci: :test,
        "lint.strict": :test,
        "static.analysis": :test
      ]
    ]
  end

  defp aliases do
    monorepo_aliases = [
      "monorepo.deps.get": ["blitz.workspace.impact deps_get --"],
      "monorepo.format": ["blitz.workspace.impact format --"],
      "monorepo.compile": ["blitz.workspace.impact compile --"],
      "monorepo.dialyzer": ["blitz.workspace.impact dialyzer --"],
      "monorepo.test": ["blitz.workspace.impact test --"]
    ]

    mr_aliases = [
      "mr.deps.get": ["monorepo.deps.get"],
      "mr.format": ["monorepo.format"],
      "mr.compile": ["monorepo.compile"],
      "mr.test": ["monorepo.test"]
    ]

    [
      "lint.strict": ["credo --config-name strict --all"],
      "static.analysis": [
        "lint.strict",
        "monorepo.dialyzer"
      ],
      ci: [
        "deps.get",
        "monorepo.deps.get",
        "monorepo.format --check-formatted",
        "monorepo.compile",
        "static.analysis",
        "monorepo.test"
      ],
      "docs.root": ["docs"]
    ] ++ monorepo_aliases ++ mr_aliases
  end

  defp blitz_workspace do
    [
      root: __DIR__,
      projects: workspace_project_globs(),
      isolation: [
        deps_path: true,
        build_path: true,
        lockfile: true,
        hex_home: "_build/hex"
      ],
      parallelism: [
        env: "CHASSIS_MONOREPO_MAX_CONCURRENCY",
        multiplier: :auto,
        base: [
          deps_get: 4,
          format: 4,
          compile: 4,
          test: 4,
          dialyzer: 4
        ],
        overrides: []
      ],
      tasks: [
        deps_get: [args: ["deps.get"], preflight?: false],
        format: [args: ["format"]],
        compile: [args: ["compile", "--warnings-as-errors"]],
        dialyzer: [
          args: ["cmd", "true"],
          mix_env: "test"
        ],
        test: [args: ["test"], mix_env: "test", color: true]
      ]
    ]
  end

  defp docs do
    guide_extras = Path.wildcard("guides/*.md")

    [
      main: "workspace_readme",
      name: "Chassis Workspace",
      logo: "assets/chassis.svg",
      assets: %{"assets" => "assets"},
      source_ref: "v#{@version}",
      source_url: @source_url,
      homepage_url: @source_url,
      extras:
        [
          {"README.md", filename: "workspace_readme"},
          "CHANGELOG.md",
          "LICENSE"
        ] ++ guide_extras,
      groups_for_extras: [
        Overview: ["README.md"],
        Guides: guide_extras,
        Project: ["CHANGELOG.md", "LICENSE"]
      ]
    ]
  end

  defp workspace_project_globs do
    [
      ".",
      "core/*",
      "bootstrap/*",
      "manager/*",
      "secrets/*",
      "adapters/*",
      "governance/*",
      "observability/*",
      "host/*",
      "evolution/*",
      "model/*",
      "proof/*"
    ]
  end
end
