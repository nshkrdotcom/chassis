# Recovery Baseline Classification (Phase 0)

This file is the canonical Phase 0 inventory mandated by
[`0540_workspace_recovery_from_generated_artifacts.md`](../../docs/20260529/chassis_impl/0540_workspace_recovery_from_generated_artifacts.md)
§1 and [`0541_implementation_readiness_corrections.md`](../../docs/20260529/chassis_impl/0541_implementation_readiness_corrections.md)
§3.2. It classifies every pre-existing artifact in the workspace into one of:

* `generated_skeleton`
* `static_cli_path`
* `non_behavioral_test`
* `bulk_checklist_mutation`
* `real_source`
* `useful_incomplete_source`
* `explicit_future_placeholder`
* `ambiguous_do_not_delete`

Generated marker modules expose `package_ref/0` and `implemented?/0 :: true`. Per
0541 §2.1, those are always `generated_skeleton`. Companion `test/package_smoke_test.exs`
files that assert only the marker are `non_behavioral_test`. Both are deleted **in
the package's activating phase**, never beforehand if removal would break the
baseline compile.

## 1. Build Support

| Path | Classification | Evidence | Action | Rationale |
| :--- | :--- | :--- | :--- | :--- |
| `build_support/full_buildout_generator.exs` | `generated_skeleton` | 2805-line bulk package generator | **Deleted in Phase 0 step A.2** | Canonical bulk generator forbidden by 0499 §3 bullet 1. |
| `build_support/dependency_sources.config.exs` | `real_source` | Canonical workspace dep graph (382 lines) | Keep | Declared canonical by 0541 §2 item 7. |
| `build_support/dependency_sources.exs` | `real_source` | Loader for the config | Keep | Required by `mix.exs`. |

## 2. CLI Router

| Path | Classification | Evidence | Action | Rationale |
| :--- | :--- | :--- | :--- | :--- |
| `manager/chassis_cli/lib/chassis/cli.ex` | `static_cli_path` | 499-line router returning hard-coded `%{status: "active", receipt_ref: "receipt:deployment:smoke", ...}` payloads for `stack.deploy`, `stack.status`, `stack.rollback`, `keys.add`, `keys.list`, `evolution.start`, `host.swap`, `tensor.reload`, etc., never dispatching to underlying packages | **Replaced in Phase 0 step C** with strict not-implemented dispatcher | Per 0541 §3.3 / 0540 §3 Step 1 / 0499 §3 bullet 2. |
| `manager/chassis_cli/lib/chassis/package/chassis_cli.ex` | `generated_skeleton` | Marker with `implemented?/0 :: true` | **Deleted in Phase 0 step C** | Per 0541 §3.3 final paragraph. |
| `manager/chassis_cli/test/package_smoke_test.exs` | `non_behavioral_test` | Asserts only `Chassis.Package.CLI.implemented?()` | **Deleted in Phase 0 step C** | Per 0541 §3.3 final paragraph. |
| `manager/chassis_cli/test/static_response_path_regression_test.exs` | `real_source` (new) | New regression test added in Phase 0 step C | Keep, must remain green every subsequent phase | Per 0541 §3.3 and 0541 §6 invariant I2. |

## 3. Core Packages

`core/chassis_contracts/lib/chassis/contracts.ex` (254 lines) contains real DTO
structs for `StackTopology`, `ServiceSpec`, `InstallationManifest`,
`ComponentManifest`, `ConfigurationProfile`, `PhysicalHost`, `BEAMNode`,
`HostProvisioningConfig`, `EnvironmentResolver`, `IsolationProfile`,
`ResidencyContract`, the `Chassis.Contracts.Adapter` behaviour, and
`NSHKR.Tenant.TenantContext`. Per 0541 §2 item 5, this file is
**`useful_incomplete_source`** and is retained to be hardened in Phase 1.

| Path | Classification | Action |
| :--- | :--- | :--- |
| `core/chassis_contracts/lib/chassis/contracts.ex` | `useful_incomplete_source` | Keep, harden in Phase 1 (property tests, redaction, codec) |
| `core/chassis_receipts/lib/chassis/receipts.ex` | `useful_incomplete_source` | Keep; Phase 2 adds Ash resources, after-action hooks, JSONL append |
| `core/chassis_inventory/lib/chassis/inventory.ex` | `useful_incomplete_source` | Keep; Phase 3 adds capacity map, placement validator, discovery |
| `core/chassis_core/lib/chassis/core.ex` | `useful_incomplete_source` | Keep; Phase 4 hardens engine with state machine and crash recovery |
| `core/chassis_environments/lib/chassis/environments.ex` | `useful_incomplete_source` | Phase 6 |
| `core/chassis_releases/lib/chassis/releases.ex` | `useful_incomplete_source` | Phase 5 |
| `core/chassis_boundary/lib/chassis/boundary.ex` | `useful_incomplete_source` | Phase 9 |
| `core/chassis_policy_boundary/lib/chassis/policy_boundary.ex` | `useful_incomplete_source` | Phase 9 |
| `core/chassis_mesh/lib/chassis/mesh.ex` | `useful_incomplete_source` | Phase 12 |
| `core/chassis_projection/lib/chassis/projection.ex` | `useful_incomplete_source` | Phase 16 |
| `core/chassis_stack/lib/chassis/stack.ex` | `useful_incomplete_source` | Phase 11 |
| `core/chassis_tenant/lib/chassis/tenant.ex` | `useful_incomplete_source` | Phase 18 |

## 4. Adapter Packages

All 8 adapter packages contain pre-existing modules that compile. Per audit, they
must be re-validated in their activating phase. Until then, classification is
`useful_incomplete_source` unless the existing module returns an unsupported
success (`{:ok, ...}`) from logic that is not implemented — in which case it is
re-classified `static_cli_path` and hardened to `{:error, {:not_implemented, __MODULE__}}`
during activation.

| Path | Classification | Activating phase |
| :--- | :--- | :--- |
| `adapters/chassis_local/lib/chassis/local.ex` | `useful_incomplete_source` | 5 |
| `adapters/chassis_ssh/lib/chassis/ssh.ex` | `useful_incomplete_source` | 7 |
| `adapters/chassis_tofu/lib/chassis/tofu.ex` | `useful_incomplete_source` | 8 |
| `adapters/chassis_systemd/lib/chassis/systemd.ex` | `useful_incomplete_source` | 13 |
| `adapters/chassis_container/lib/chassis/container.ex` | `useful_incomplete_source` | 14 |
| `adapters/chassis_k8s/lib/chassis/k8s.ex` | `useful_incomplete_source` | 15 |
| `adapters/chassis_hf_hub/lib/chassis/hf_hub.ex` | `useful_incomplete_source` | 40 |
| `adapters/chassis_artifact_fs/lib/chassis/artifact_fs.ex` | `useful_incomplete_source` | 39 |

## 5. Secrets Packages

| Path | Classification | Activating phase |
| :--- | :--- | :--- |
| `secrets/chassis_secret_refs/lib/chassis/secret_refs.ex` | `useful_incomplete_source` | 10 |
| `secrets/chassis_secret_env/lib/chassis/secret_env.ex` | `useful_incomplete_source` | 10 |
| `secrets/chassis_secret_sops/lib/chassis/secret_sops.ex` | `useful_incomplete_source` | 10 |
| `secrets/chassis_secret_vault/lib/chassis/secret_vault.ex` | `useful_incomplete_source` | 10 |

## 6. Bootstrap / Governance / Observability / Host / Evolution / Model / Proof

| Path | Classification | Activating phase |
| :--- | :--- | :--- |
| `bootstrap/chassis_bootstrap/lib/chassis/bootstrap.ex` | `useful_incomplete_source` | 7 |
| `bootstrap/chassis_doctor/lib/chassis/doctor.ex` | `useful_incomplete_source` | 3 |
| `bootstrap/chassis_installer/lib/chassis/installer.ex` | `useful_incomplete_source` | 13 |
| `governance/chassis_appkit_surface/lib/chassis/appkit_surface.ex` | `useful_incomplete_source` | 16 |
| `governance/chassis_mezzanine_bridge/lib/chassis/mezzanine_bridge.ex` | `static_cli_path` (returns static `outbox_ref: "outbox:chassis:smoke"`) | 17 (replace with real Mezzanine outbox dispatch) |
| `observability/chassis_aitrace_bridge/lib/chassis/aitrace_bridge.ex` | `useful_incomplete_source` | 19 |
| `observability/chassis_metrics/lib/chassis/metrics.ex` | `useful_incomplete_source` | 19 |
| `host/chassis_host_daemon/lib/chassis/host_daemon.ex` | `useful_incomplete_source` | 29 |
| `host/chassis_swap_supervisor/lib/chassis/swap_supervisor.ex` | `useful_incomplete_source` | 30 |
| `host/chassis_trial_supervisor/lib/chassis/trial_supervisor.ex` | `useful_incomplete_source` | 28 |
| `host/chassis_health_probe/lib/chassis/health_probe.ex` | `useful_incomplete_source` | 30 |
| `evolution/chassis_evolution_contracts/lib/chassis/evolution_contracts.ex` | `useful_incomplete_source` | 22 |
| `evolution/chassis_failure_batches/lib/chassis/failure_batches.ex` | `useful_incomplete_source` | 23 |
| `evolution/chassis_evolution_core/lib/chassis/evolution_core.ex` | `useful_incomplete_source` | 24 |
| `evolution/chassis_coding_agent_runner/lib/chassis/coding_agent_runner.ex` | `useful_incomplete_source` | 25 |
| `evolution/chassis_candidate_registry/lib/chassis/candidate_registry.ex` | `useful_incomplete_source` | 26 |
| `evolution/chassis_trial_runtime/lib/chassis/trial_runtime.ex` | `useful_incomplete_source` | 27 |
| `evolution/chassis_candidate_scoring/lib/chassis/candidate_scoring.ex` | `useful_incomplete_source` | 32 |
| `evolution/chassis_evolution_receipts/lib/chassis/evolution_receipts.ex` | `useful_incomplete_source` | 33 |
| `model/chassis_weight_materializer/lib/chassis/weight_materializer.ex` | `useful_incomplete_source` | 40 |
| `model/chassis_model_cache/lib/chassis/model_cache.ex` | `useful_incomplete_source` | 40 |
| `model/chassis_hardware_guard/lib/chassis/hardware_guard.ex` | `useful_incomplete_source` | 41 |
| `model/chassis_tensor_reload/lib/chassis/tensor_reload.ex` | `useful_incomplete_source` | 42 |
| `proof/chassis_fixtures/lib/chassis/fixtures.ex` | `useful_incomplete_source` | 21 |
| `proof/chassis_conformance/lib/chassis/conformance.ex` | `useful_incomplete_source` | 21 |
| `proof/chassis_stacklab_bridge/lib/chassis/stacklab_bridge.ex` | `static_cli_path` (returns hard-coded `{:ok, %{passed: 12, failed: 0}}`) | 21 (replace with structured `mix stack_lab.run --json` dispatch) |
| `proof/chassis_evolution_conformance/lib/chassis/evolution_conformance.ex` | `useful_incomplete_source` | 36 |
| `proof/chassis_model_asset_conformance/lib/chassis/model_asset_conformance.ex` | `useful_incomplete_source` | 41 |
| `manager/chassis_stack_manager/lib/chassis/stack_manager.ex` | `static_cli_path` (returns hard-coded `%{status: :active, receipt_ref: "receipt:deployment:smoke"}` and `%{status: :rolled_back, rollback_ref: "rollback:smoke"}`) | 11 (replace with real transaction state machine) |

## 7. Generated Marker Modules (`*/lib/chassis/package/chassis_*.ex`)

All 54 marker files of the form `Chassis.Package.<Name>` are
**`generated_skeleton`** per 0541 §2 item 1. They are not deleted in Phase 0 because
some packages currently depend on no other module to compile. Each marker MUST be
deleted in its package's activating phase and never count as implementation
evidence (per 0541 §6 invariant I3).

Action for the 54 marker files: **Delete in activating phase**.

## 8. Generated Smoke Tests (`*/test/package_smoke_test.exs`)

All 54 generated smoke tests are **`non_behavioral_test`** per 0541 §2 item 2.
Each MUST be deleted in its package's activating phase and replaced with
behavioral coverage that exercises real public functions, returned state, and
unhappy paths.

Action for the 54 smoke files: **Delete in activating phase**.

## 9. Pending Review

Items surfaced during Phase 0 grep audit that require classification in their
activating phase rather than now:

* `manager/chassis_stack_manager/lib/chassis/stack_manager.ex` returns
  `receipt:deployment:smoke` — must be re-derived from real
  `Chassis.Receipts.DeploymentRecord.new_ref/0` in Phase 11.
* `proof/chassis_stacklab_bridge/lib/chassis/stacklab_bridge.ex` returns
  `%{passed: 12, failed: 0}` unconditionally — must be re-derived from real
  `mix stack_lab.run --json` output in Phase 21.
* `governance/chassis_mezzanine_bridge/lib/chassis/mezzanine_bridge.ex` returns
  `outbox_ref: "outbox:chassis:smoke"` — must publish through the real Mezzanine
  outbox in Phase 17.
* `manager/chassis_cli/lib/chassis/cli.ex` (the entire 499-line file) — replaced
  wholesale in Phase 0 step C below.
