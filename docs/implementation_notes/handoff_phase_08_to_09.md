# Handoff — Phases 0-8 complete; resume at Phase 9

Per `0499_execution_integrity_contract.md` §7. Nine phases done in this
session; 17 packages activated and hardened end-to-end with TDD; all CLI
invariants remain green throughout.

## Last completed phase

**Phase 8 — Infrastructure Adapters (6 packages).** Commit `83fdc65` in
`~/p/g/n/chassis`.

## Session totals

| Phase | Package(s) | Behavioral tests |
| :-- | :-- | --: |
| 0 | Workspace recovery (CLI + facades) | — |
| 1 | `chassis_contracts` | 23 |
| 2 | `chassis_receipts` | 18 |
| 3 | `chassis_inventory` | 25 |
| 4 | `chassis_core` (Engine + Dispatcher + NodeRegistry) | 19 |
| 5 | `chassis_stack` (4 profiles, ProfileResolver, Composer) | 18 |
| 6 | `chassis_environments` (compile-time JSON embedding) | 17 |
| 7 | `chassis_bootstrap` + `chassis_doctor` + `chassis_installer` | 34 |
| 8 | 6 adapters (`local`, `systemd`, `ssh`, `artifact_fs`, `tofu`, `k8s`) | 54 |
| — | static-CLI invariants (manager + workspace root) | 18 |
| **Total** | **17 packages** | **226 tests, 0 failures** |

`mix monorepo.compile --warnings-as-errors` → `Blitz impact summary:
selected=17 skipped=38 total=55` (every selected package green).

## Commit hashes per repo (latest 12)

`~/p/g/n/chassis` (pushed):
* `83fdc65` Phase 8: 6 infra adapters
* `6b229da` Phase 7: bootstrap+doctor+installer
* `3a0187d` Handoff phase 06→07
* `e9de06f` Phase 6: chassis_environments
* `bd2bf77` Phase 5: chassis_stack
* `fcd68cd` Phase 4: chassis_core + Engine
* `bad07ad` Handoff phase 03→04
* `159ab6e` Phase 3: chassis_inventory
* `80f0b71` Phase 2: chassis_receipts
* `be278bd` Phase 1 report
* `1012cb0` Phase 1: chassis_contracts
* Plus 6 Phase 0 commits

`~/p/g/j/jido_brainstorm/nshkrdotcom` (pushed) — 9 commits, one per phase.

## Known gaps still tracked

37 of the 54 leaf packages remain on the generated marker + smoke pattern
classified in `recovery_baseline.md`. Each is scheduled for activation in
a specific later phase per 0537 §3. None block compilation or the active
set's test runs.

Static smoke artifacts remain at:
* `manager/chassis_stack_manager/lib/chassis/stack_manager.ex` → Phase 11
* `governance/chassis_mezzanine_bridge/lib/chassis/mezzanine_bridge.ex` → Phase 17
* `proof/chassis_stacklab_bridge/lib/chassis/stacklab_bridge.ex` → Phase 21
* `host/chassis_swap_supervisor/lib/chassis/swap_supervisor.ex`,
  `host/chassis_health_probe/lib/chassis/health_probe.ex` → Phases 31-33
* `model/chassis_model_cache/lib/chassis/model_cache.ex` → Phase 39

## Exact next phase

**Phase 9 — `core/chassis_mesh` + real BEAM TLS mesh.**

Permitted package set per 0537 §3 Phase 9:
* `core/chassis_mesh`

Permitted to depend on (all already activated):
`chassis_contracts`, `chassis_receipts`, `chassis_inventory`,
`chassis_core`, `chassis_stack`, `chassis_environments`,
`chassis_bootstrap`, `chassis_doctor`, `chassis_installer`, and any
Phase 8 adapter.

Phase 9 checklist items (from 0503 lines ~308-330):
* `Chassis.Mesh.Adapter` behaviour per 0508 §1
* `Chassis.Mesh.BEAMDistribution` per 0508 §2 with real TLS cert generation
* `Chassis.Mesh.TlsKit` generating per-cluster CA + per-node certs via
  `:public_key` + `:crypto`
* `Chassis.Mesh.LocalLoopback` for monolith dev
* `Chassis.Mesh.HealthSupervisor` per 0523 §2 (basic loop; rollback
  dispatch comes in Phase 23)
* `:pg` group sync per virtual server
* Multi-node integration test (3 `iex --name x@127.0.0.1` nodes, assert
  TLS mesh formation + `:pg.get_members/2` cross-node lookup)
* Spine Audit: `inet_dist_listen_min/max` ports configurable

Test-first rhythm: write failing tests for cert generation, TLS
distribution `:net_kernel.start/1` shape, `:pg` group sync, health probe;
implement; delete the package marker + smoke test; verify static-CLI
invariants still green; write `phase_09_report.md`; commit and push.

Live 3-node integration may need DEFERRED inline annotation if the
sandbox cannot start additional BEAM nodes (it usually can; epmd is
available in most environments). The TLS cert generation surface is
fully testable in-process via `:public_key.pkix_test_data/1`.

## Cheat-sheet for the next 5 phases (from 0537 §3)

* Phase 9: `core/chassis_mesh`
* Phase 10: `secrets/chassis_secret_refs`, `chassis_secret_env`,
  `chassis_secret_sops`, `chassis_secret_vault` (4 packages)
* Phase 11: `core/chassis_releases`, `manager/chassis_stack_manager` —
  **first phase that begins wiring real `Chassis.CLI.Command.Stack.*`
  modules**; the static-CLI regression tests start swapping
  `not_implemented` payloads for real dispatched calls. See the
  `static_response_path_regression_test.exs` invariant.
* Phase 12: `core/chassis_boundary` (Ring 0 envelopes, GroundPlane
  integration that was DEFERRED in Phase 1)
* Phase 13: `core/chassis_policy_boundary` (Citadel authority)

## Reading order on resume

1. `0499_execution_integrity_contract.md`
2. `0541_implementation_readiness_corrections.md` (binding corrections)
3. `0540_workspace_recovery_from_generated_artifacts.md`
4. `0537_chassis_full_ecosystem_package_map.md` §3 Phase 9
5. `0503_implementation_checklist.md` Phase 9 (lines ~308-330)
6. `0508_mesh_and_discovery_architecture.md` §§1-2
7. `0523_metabolic_and_self_healing_spec.md` §2 (HealthSupervisor surface)
8. This handoff
9. `docs/implementation_notes/recovery_baseline.md` (skim)
