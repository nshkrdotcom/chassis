# Handoff — Phases 0-9 complete; resume at Phase 10

Per `0499_execution_integrity_contract.md` §7. **Ten phases done in this
session**; 18 packages activated end-to-end with TDD; every CLI invariant
remains green throughout.

## Last completed phase

**Phase 9 — `core/chassis_mesh` + real BEAM TLS mesh.**
Commit `c216fd8` in `~/p/g/n/chassis`.

## Session totals

| Phase | Package(s) | Tests |
| :-- | :-- | --: |
| 0 | Workspace recovery (CLI + facades) | — |
| 1 | `chassis_contracts` | 23 |
| 2 | `chassis_receipts` | 18 |
| 3 | `chassis_inventory` | 25 |
| 4 | `chassis_core` Engine | 19 |
| 5 | `chassis_stack` profiles | 18 |
| 6 | `chassis_environments` JSON embed | 17 |
| 7 | `chassis_bootstrap` + `chassis_doctor` + `chassis_installer` | 34 |
| 8 | 6 adapters (`local`, `systemd`, `ssh`, `artifact_fs`, `tofu`, `k8s`) | 54 |
| 9 | `chassis_mesh` TLS + `:pg` + HealthSupervisor | 17 |
| — | static-CLI invariants (manager + workspace root) | 18 |
| **Total** | **18 packages** | **243 tests, 0 failures** |

`mix monorepo.compile --warnings-as-errors` → `Blitz impact summary:
selected=18 skipped=37 total=55`.

## Commit hashes (latest first)

`~/p/g/n/chassis` (pushed):
* `c216fd8` Phase 9: chassis_mesh
* `b0451c6` Handoff 08→09
* `83fdc65` Phase 8: 6 adapters
* `6b229da` Phase 7: bootstrap+doctor+installer
* `3a0187d` Handoff 06→07
* `e9de06f` Phase 6: chassis_environments
* `bd2bf77` Phase 5: chassis_stack
* `fcd68cd` Phase 4: chassis_core
* `bad07ad` Handoff 03→04
* `159ab6e` Phase 3: chassis_inventory
* `80f0b71` Phase 2: chassis_receipts
* `be278bd` Phase 1 report; `1012cb0` Phase 1: chassis_contracts
* 6 Phase 0 commits (recovery)

`~/p/g/j/jido_brainstorm/nshkrdotcom` (pushed): 10 checklist-edit commits,
one per phase.

## Known gaps still tracked (unchanged from prior handoff)

36 of the 54 leaf packages remain on the generated marker + smoke
pattern, scheduled for activation in their assigned phase.

Static smoke artifacts to harden when their phase arrives:
* `manager/chassis_stack_manager` → Phase 11
* `governance/chassis_mezzanine_bridge` → Phase 17
* `proof/chassis_stacklab_bridge` → Phase 21
* `host/chassis_swap_supervisor`, `chassis_health_probe` → Phases 31-33
* `model/chassis_model_cache` → Phase 39

## Exact next phase

**Phase 10 — Secrets Plane.** Permitted packages per 0537 §3 Phase 10:
* `secrets/chassis_secret_refs`
* `secrets/chassis_secret_env`
* `secrets/chassis_secret_sops`
* `secrets/chassis_secret_vault`

Four packages. The SOPS package is the largest; it needs:
* `Chassis.Secrets.Materializer` behaviour
* `Chassis.Secrets.Materializer.Env` (read from env var → lease)
* `Chassis.Secrets.Materializer.Sops` (decrypt SOPS file → lease)
* `Chassis.Secrets.LeaseSupervisor` with ephemeral material + cleanup
* `Chassis.Secrets.SecretRef` typed handle
* `Chassis.Secrets.Vault` — placeholder per 0541 §1 row 4

Phase 10 must NOT leak raw secret bytes to:
* Receipts (already guarded in Phase 2; assert with new tests)
* JSONL appender (already guarded; assert)
* Inspect output (verify `defimpl Inspect` on `SecretRef` / `Lease`)
* Crash reports (no `pid:` / `material:` in `Exception.message/1`)

SOPS itself: the real `sops --decrypt` CLI is the standard production
path. Use a `:sops_backend` injection so tests use a Fake decryptor that
records calls; live `sops` runs at the Phase 10 QC gate when sops is
available.

Test-first rhythm:
1. Write failing tests for each of the 4 packages (lease materialization,
   redaction, cleanup, refs)
2. Implement
3. Delete each package's marker + smoke
4. Verify static-CLI invariants still green
5. Write `phase_10_report.md`
6. Commit + push

## Cheat-sheet for Phases 11-14 (next-next)

* Phase 11: `core/chassis_releases`, `manager/chassis_stack_manager` —
  **first phase that wires real `Chassis.CLI.Command.Stack.*` modules.**
  The static-CLI regression test continues to require that every command
  either routes through a real `Chassis.CLI.Command.*` module or returns
  the canonical `not_implemented` map. When the command module exists,
  the test must still pass — the `:command` key gets stamped by the
  router. Pay attention.
* Phase 12: `core/chassis_boundary` (Ring 0 envelopes, GroundPlane.Codec
  integration deferred in Phase 1)
* Phase 13: `core/chassis_policy_boundary` (Citadel authority)
* Phase 14: `observability/chassis_aitrace_bridge`

## Reading order on resume

1. `0499_execution_integrity_contract.md` (mandatory recap)
2. `0541_implementation_readiness_corrections.md` (binding corrections)
3. `0537_chassis_full_ecosystem_package_map.md` §3 Phase 10
4. `0503_implementation_checklist.md` Phase 10 (lines ~328-365)
5. `0510_secrets_and_credentials.md` (Secrets Plane spec)
6. This handoff
7. `docs/implementation_notes/recovery_baseline.md` (skim for gaps)
