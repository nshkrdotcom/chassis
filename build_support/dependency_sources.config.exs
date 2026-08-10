%{
  deps: %{
    :aitrace => %{
      path: "../AITrace",
      github: %{repo: "nshkrdotcom/AITrace", branch: "main"},
      hex: "~> 0.1.0",
      default_order: [:path, :github, :hex],
      publish_order: [:hex]
    },
    :blitz => %{
      hex: "~> 0.3.0",
      default_order: [:hex],
      publish_order: [:hex]
    },
    :citadel_authority_contract => %{
      path: "../citadel/core/authority_contract",
      github: %{
        repo: "nshkrdotcom/citadel",
        branch: "main",
        subdir: "core/authority_contract"
      },
      hex: "~> 0.1.0",
      default_order: [:path, :github, :hex],
      publish_order: [:hex]
    },
    :citadel_governance => %{
      path: "../citadel/core/citadel_governance",
      github: %{
        repo: "nshkrdotcom/citadel",
        branch: "main",
        subdir: "core/citadel_governance"
      },
      hex: "~> 0.1.0",
      default_order: [:path, :github, :hex],
      publish_order: [:hex]
    },
    :ground_plane_contracts => %{
      path: "../ground_plane/core/ground_plane_contracts",
      github: %{
        repo: "nshkrdotcom/ground_plane",
        branch: "main",
        subdir: "core/ground_plane_contracts"
      },
      hex: "~> 0.1.0",
      default_order: [:path, :github, :hex],
      publish_order: [:hex]
    },
    :weld => %{
      hex: "~> 0.8.4",
      default_order: [:hex],
      publish_order: [:hex]
    },
    :chassis_contracts => %{
      path: "core/chassis_contracts",
      default_order: [:path],
      publish_order: [:hex],
      hex: "~> 0.1",
      opts: []
    },
    :chassis_receipts => %{
      path: "core/chassis_receipts",
      default_order: [:path],
      publish_order: [:hex],
      hex: "~> 0.1",
      opts: []
    },
    :chassis_inventory => %{
      path: "core/chassis_inventory",
      default_order: [:path],
      publish_order: [:hex],
      hex: "~> 0.1",
      opts: []
    },
    :chassis_environments => %{
      path: "core/chassis_environments",
      default_order: [:path],
      publish_order: [:hex],
      hex: "~> 0.1",
      opts: []
    },
    :chassis_core => %{
      path: "core/chassis_core",
      default_order: [:path],
      publish_order: [:hex],
      hex: "~> 0.1",
      opts: []
    },
    :chassis_boundary => %{
      path: "core/chassis_boundary",
      default_order: [:path],
      publish_order: [:hex],
      hex: "~> 0.1",
      opts: []
    },
    :chassis_policy_boundary => %{
      path: "core/chassis_policy_boundary",
      default_order: [:path],
      publish_order: [:hex],
      hex: "~> 0.1",
      opts: []
    },
    :chassis_tenant => %{
      path: "core/chassis_tenant",
      default_order: [:path],
      publish_order: [:hex],
      hex: "~> 0.1",
      opts: []
    },
    :chassis_stack => %{
      path: "core/chassis_stack",
      default_order: [:path],
      publish_order: [:hex],
      hex: "~> 0.1",
      opts: []
    },
    :chassis_mesh => %{
      path: "core/chassis_mesh",
      default_order: [:path],
      publish_order: [:hex],
      hex: "~> 0.1",
      opts: []
    },
    :chassis_releases => %{
      path: "core/chassis_releases",
      default_order: [:path],
      publish_order: [:hex],
      hex: "~> 0.1",
      opts: []
    },
    :chassis_projection => %{
      path: "core/chassis_projection",
      default_order: [:path],
      publish_order: [:hex],
      hex: "~> 0.1",
      opts: []
    },
    :chassis_bootstrap => %{
      path: "bootstrap/chassis_bootstrap",
      default_order: [:path],
      publish_order: [:hex],
      hex: "~> 0.1",
      opts: []
    },
    :chassis_doctor => %{
      path: "bootstrap/chassis_doctor",
      default_order: [:path],
      publish_order: [:hex],
      hex: "~> 0.1",
      opts: []
    },
    :chassis_installer => %{
      path: "bootstrap/chassis_installer",
      default_order: [:path],
      publish_order: [:hex],
      hex: "~> 0.1",
      opts: []
    },
    :chassis_cli => %{
      path: "manager/chassis_cli",
      default_order: [:path],
      publish_order: [:hex],
      hex: "~> 0.1",
      opts: []
    },
    :chassis_stack_manager => %{
      path: "manager/chassis_stack_manager",
      default_order: [:path],
      publish_order: [:hex],
      hex: "~> 0.1",
      opts: []
    },
    :chassis_secret_refs => %{
      path: "secrets/chassis_secret_refs",
      default_order: [:path],
      publish_order: [:hex],
      hex: "~> 0.1",
      opts: []
    },
    :chassis_secret_env => %{
      path: "secrets/chassis_secret_env",
      default_order: [:path],
      publish_order: [:hex],
      hex: "~> 0.1",
      opts: []
    },
    :chassis_secret_sops => %{
      path: "secrets/chassis_secret_sops",
      default_order: [:path],
      publish_order: [:hex],
      hex: "~> 0.1",
      opts: []
    },
    :chassis_secret_vault => %{
      path: "secrets/chassis_secret_vault",
      default_order: [:path],
      publish_order: [:hex],
      hex: "~> 0.1",
      opts: []
    },
    :chassis_local => %{
      path: "adapters/chassis_local",
      default_order: [:path],
      publish_order: [:hex],
      hex: "~> 0.1",
      opts: []
    },
    :chassis_systemd => %{
      path: "adapters/chassis_systemd",
      default_order: [:path],
      publish_order: [:hex],
      hex: "~> 0.1",
      opts: []
    },
    :chassis_ssh => %{
      path: "adapters/chassis_ssh",
      default_order: [:path],
      publish_order: [:hex],
      hex: "~> 0.1",
      opts: []
    },
    :chassis_artifact_fs => %{
      path: "adapters/chassis_artifact_fs",
      default_order: [:path],
      publish_order: [:hex],
      hex: "~> 0.1",
      opts: []
    },
    :chassis_tofu => %{
      path: "adapters/chassis_tofu",
      default_order: [:path],
      publish_order: [:hex],
      hex: "~> 0.1",
      opts: []
    },
    :chassis_k8s => %{
      path: "adapters/chassis_k8s",
      default_order: [:path],
      publish_order: [:hex],
      hex: "~> 0.1",
      opts: []
    },
    :chassis_container => %{
      path: "adapters/chassis_container",
      default_order: [:path],
      publish_order: [:hex],
      hex: "~> 0.1",
      opts: []
    },
    :chassis_hf_hub => %{
      path: "adapters/chassis_hf_hub",
      default_order: [:path],
      publish_order: [:hex],
      hex: "~> 0.1",
      opts: []
    },
    :chassis_appkit_surface => %{
      path: "governance/chassis_appkit_surface",
      default_order: [:path],
      publish_order: [:hex],
      hex: "~> 0.1",
      opts: []
    },
    :chassis_mezzanine_bridge => %{
      path: "governance/chassis_mezzanine_bridge",
      default_order: [:path],
      publish_order: [:hex],
      hex: "~> 0.1",
      opts: []
    },
    :chassis_aitrace_bridge => %{
      path: "observability/chassis_aitrace_bridge",
      default_order: [:path],
      publish_order: [:hex],
      hex: "~> 0.1",
      opts: []
    },
    :chassis_metrics => %{
      path: "observability/chassis_metrics",
      default_order: [:path],
      publish_order: [:hex],
      hex: "~> 0.1",
      opts: []
    },
    :chassis_host_daemon => %{
      path: "host/chassis_host_daemon",
      default_order: [:path],
      publish_order: [:hex],
      hex: "~> 0.1",
      opts: []
    },
    :chassis_swap_supervisor => %{
      path: "host/chassis_swap_supervisor",
      default_order: [:path],
      publish_order: [:hex],
      hex: "~> 0.1",
      opts: []
    },
    :chassis_trial_supervisor => %{
      path: "host/chassis_trial_supervisor",
      default_order: [:path],
      publish_order: [:hex],
      hex: "~> 0.1",
      opts: []
    },
    :chassis_health_probe => %{
      path: "host/chassis_health_probe",
      default_order: [:path],
      publish_order: [:hex],
      hex: "~> 0.1",
      opts: []
    },
    :chassis_evolution_contracts => %{
      path: "evolution/chassis_evolution_contracts",
      default_order: [:path],
      publish_order: [:hex],
      hex: "~> 0.1",
      opts: []
    },
    :chassis_evolution_core => %{
      path: "evolution/chassis_evolution_core",
      default_order: [:path],
      publish_order: [:hex],
      hex: "~> 0.1",
      opts: []
    },
    :chassis_failure_batches => %{
      path: "evolution/chassis_failure_batches",
      default_order: [:path],
      publish_order: [:hex],
      hex: "~> 0.1",
      opts: []
    },
    :chassis_candidate_registry => %{
      path: "evolution/chassis_candidate_registry",
      default_order: [:path],
      publish_order: [:hex],
      hex: "~> 0.1",
      opts: []
    },
    :chassis_trial_runtime => %{
      path: "evolution/chassis_trial_runtime",
      default_order: [:path],
      publish_order: [:hex],
      hex: "~> 0.1",
      opts: []
    },
    :chassis_candidate_scoring => %{
      path: "evolution/chassis_candidate_scoring",
      default_order: [:path],
      publish_order: [:hex],
      hex: "~> 0.1",
      opts: []
    },
    :chassis_coding_agent_runner => %{
      path: "evolution/chassis_coding_agent_runner",
      default_order: [:path],
      publish_order: [:hex],
      hex: "~> 0.1",
      opts: []
    },
    :chassis_evolution_receipts => %{
      path: "evolution/chassis_evolution_receipts",
      default_order: [:path],
      publish_order: [:hex],
      hex: "~> 0.1",
      opts: []
    },
    :chassis_weight_materializer => %{
      path: "model/chassis_weight_materializer",
      default_order: [:path],
      publish_order: [:hex],
      hex: "~> 0.1",
      opts: []
    },
    :chassis_hardware_guard => %{
      path: "model/chassis_hardware_guard",
      default_order: [:path],
      publish_order: [:hex],
      hex: "~> 0.1",
      opts: []
    },
    :chassis_tensor_reload => %{
      path: "model/chassis_tensor_reload",
      default_order: [:path],
      publish_order: [:hex],
      hex: "~> 0.1",
      opts: []
    },
    :chassis_model_cache => %{
      path: "model/chassis_model_cache",
      default_order: [:path],
      publish_order: [:hex],
      hex: "~> 0.1",
      opts: []
    },
    :chassis_conformance => %{
      path: "proof/chassis_conformance",
      default_order: [:path],
      publish_order: [:hex],
      hex: "~> 0.1",
      opts: []
    },
    :chassis_fixtures => %{
      path: "proof/chassis_fixtures",
      default_order: [:path],
      publish_order: [:hex],
      hex: "~> 0.1",
      opts: []
    },
    :chassis_stacklab_bridge => %{
      path: "proof/chassis_stacklab_bridge",
      default_order: [:path],
      publish_order: [:hex],
      hex: "~> 0.1",
      opts: []
    },
    :chassis_evolution_conformance => %{
      path: "proof/chassis_evolution_conformance",
      default_order: [:path],
      publish_order: [:hex],
      hex: "~> 0.1",
      opts: []
    },
    :chassis_model_asset_conformance => %{
      path: "proof/chassis_model_asset_conformance",
      default_order: [:path],
      publish_order: [:hex],
      hex: "~> 0.1",
      opts: []
    }
  }
}
