# Handoff — Phases 0-6 complete; resume at Phase 7

Per `0499_execution_integrity_contract.md` §7 "Safe Phase-Boundary Rotation".
Seven phases done back-to-back in one session; all CLI invariants stay green;
seven foundational packages hardened.

## Last completed phase

**Phase 6 — `chassis_environments`.** Commit `e9de06f` in `~/p/g/n/chassis`.

## Commit hashes per repo

* `~/p/g/n/chassis` (pushed to `origin/main`):
  * Phase 0 (5 commits): `4e36654`, `497fbcd`, `cdae64a`, `a618f3e`,
    `22d751e`, `1afacc6` (closing)
  * Phase 1: `1012cb0` impl + `be278bd` report
  * Phase 2: `80f0b71` impl + report
  * Phase 3: `159ab6e` impl + report + handoff (`bad07ad`)
  * Phase 4: `fcd68cd` impl + report
  * Phase 5: `bd2bf77` impl + report
  * Phase 6: `e9de06f` impl + report
* `~/p/g/j/jido_brainstorm/nshkrdotcom` (pushed):
  * `c43d43b`, `2b1519a`, `19835a3`, `d85a670`, `9dd7558`, `830570c`, `c4c30e9`

## Tests run and results

```
manager/chassis_cli              12/12 PASS (static-CLI invariant)
workspace root (./)               6/6  PASS (root static-CLI invariant)
core/chassis_contracts           23/23 PASS
core/chassis_receipts            18/18 PASS
core/chassis_inventory           25/25 PASS
core/chassis_core                19/19 PASS
core/chassis_stack               18/18 PASS
core/chassis_environments        17/17 PASS
mix monorepo.compile --warnings-as-errors    selected=8/55 all green
```

Total behavioral tests written this session: **120** + 18 CLI invariants
= 138 tests, 0 failures.

## Checklist items completed (canonical 0503)

* Phase 0: 17 items + safe checklist reset
* Phase 1: 15 items + 1 DEFERRED inline (`GroundPlane.Boundary.Codec` → Phase 9)
* Phase 2: 16 items + 1 DEFERRED inline (AshPostgres backend → Phase 11/18)
* Phase 3: 13 items + 1 DEFERRED inline (dynamic HTTP clients → Phase 8)
* Phase 4: 10 items + 1 DEFERRED inline (stream_data → Phase 8+)
* Phase 5: 9 items
* Phase 6: 14 items

Every checked box has a corresponding `docs/implementation_notes/phase_NN_report.md`
showing failing-test → impl → passing-test evidence and the canonical
classification of every Execution Integrity grep match.

## Known gaps still tracked

The 46 remaining generated `Chassis.Package.<Name>` markers + their
`package_smoke_test.exs` files continue to live in untouched packages. They
are inventoried in `docs/implementation_notes/recovery_baseline.md` and
will be removed plus replaced with behavioral coverage in each package's
activating phase. They do not block compilation or any active package's
test run.

Static smoke artifacts remain at:
* `manager/chassis_stack_manager/lib/chassis/stack_manager.ex` →
  re-derive in Phase 11
* `governance/chassis_mezzanine_bridge/lib/chassis/mezzanine_bridge.ex` →
  re-derive in Phase 17
* `proof/chassis_stacklab_bridge/lib/chassis/stacklab_bridge.ex` →
  re-derive in Phase 21
* `host/chassis_swap_supervisor/lib/chassis/swap_supervisor.ex`,
  `host/chassis_health_probe/lib/chassis/health_probe.ex`,
  `model/chassis_model_cache/lib/chassis/model_cache.ex` → Phase 30-40

Each is also documented in `recovery_baseline.md` §9 "Pending Review".

## Exact next phase

**Phase 7 — `bootstrap/chassis_bootstrap`, `bootstrap/chassis_doctor`,
`bootstrap/chassis_installer`.** Permitted package set per 0537 §3 Phase 7:

* `bootstrap/chassis_bootstrap`
* `bootstrap/chassis_doctor`
* `bootstrap/chassis_installer`

Permitted to depend on (already activated):
`chassis_contracts`, `chassis_receipts`, `chassis_inventory`,
`chassis_core`, `chassis_stack`, `chassis_environments`.

Phase 7 checklist items (from 0503 lines ~248-285) cover:
* `Chassis.Bootstrap` orchestrator that runs SSH-based host bootstrap and
  emits `Chassis.Receipts.ProvisioningRecord` per step
* `Chassis.Doctor` health-check runner (BEAM alive, mesh connectivity)
* `Chassis.Installer` release-bundle installer (paths from environments)
* Per-phase fixtures live under each activating package's
  `lib/.../fixtures.ex` (per 0541 §4.3)
* Mix tasks: `mix chassis.host.bootstrap.smoke`,
  `mix chassis.node.doctor`, `mix chassis.node.bootstrap`

Phase 7 is the first phase where SSH adapter activation is teased but
NOT yet implemented — per 0537 §3, `adapters/chassis_ssh` lands in
Phase 8. In Phase 7, the SSH path stays behind a `{:error,
{:not_implemented, Chassis.Adapters.SSH}}` placeholder while bootstrap
shape and receipt emission are tested with a fake transport.

Test-first rhythm: write tests for each phase package that exercise
real GenServer / state-machine / receipt-emission behavior; implement;
delete each package's marker and smoke test; run static-CLI invariants;
write `phase_07_report.md`; commit and push.

## Next-5-phase cheat sheet (from 0537 §3)

* Phase 7: `bootstrap/chassis_bootstrap`, `chassis_doctor`, `chassis_installer`
* Phase 8: `adapters/chassis_local`, `chassis_systemd`, `chassis_ssh`,
  `chassis_artifact_fs`, `chassis_tofu`, `chassis_k8s`
* Phase 9: `core/chassis_mesh`
* Phase 10: `secrets/chassis_secret_refs`, `chassis_secret_env`,
  `chassis_secret_sops`, `chassis_secret_vault`
* Phase 11: `core/chassis_releases`, `manager/chassis_stack_manager`

Phase 11 is the first phase where the CLI begins to wire real
`Chassis.CLI.Command.Stack.*` modules and the static_response_path
regression test starts swapping `not_implemented` payloads for real
dispatched calls. Until then, the CLI invariant remains "every command
routes through `Chassis.CLI.Command.*` and unactivated ones return the
canonical `not_implemented` map."
