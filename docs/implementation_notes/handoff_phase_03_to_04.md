# Handoff — Phases 0-3 complete; resume at Phase 4

Per `0499_execution_integrity_contract.md` §7 "Safe Phase-Boundary Rotation".
This is a clean phase boundary; all CLI invariants are green and the four
foundational packages (`chassis_contracts`, `chassis_receipts`,
`chassis_inventory`) plus the static-CLI guard are hardened.

## Last completed phase

**Phase 3 — `chassis_inventory`.** Commit `159ab6e` in `~/p/g/n/chassis`.

## Commit hashes per repo

* `~/p/g/n/chassis` (pushed to `origin/main` at `n:nshkrdotcom/chassis.git`):
  * `4e36654` — Phase 0 step A: quarantine bulk generator
  * `497fbcd` — Phase 0 step A.2: delete bulk generator
  * `cdae64a` — Phase 0 step B: recovery baseline classification table
  * `a618f3e` — Phase 0 step C: replace manager/chassis_cli static router
  * `22d751e` — Phase 0 step C.2: replace workspace-root static router + facades
  * `1afacc6` — Phase 0 step F: closing commit
  * `1012cb0` — Phase 1: chassis_contracts hardened
  * `be278bd` — Phase 1 report
  * `80f0b71` — Phase 2: chassis_receipts hardened
  * `159ab6e` — Phase 3: chassis_inventory hardened
* `~/p/g/j/jido_brainstorm/nshkrdotcom` (pushed to `origin/main` at `n:nshkrdotcom/brainstorms`):
  * `c43d43b` — Phase 0 checkbox edits
  * `2b1519a` — Phase 1 checkbox edits
  * `19835a3` — Phase 2 checkbox edits
  * `d85a670` — Phase 3 checkbox edits

## Tests run and results

```
manager/chassis_cli       12/12 PASS  (static_response_path_regression_test.exs)
workspace root (./)        6/6  PASS  (root_cli_static_response_path_regression_test.exs)
core/chassis_contracts    23/23 PASS  (contracts_test.exs)
core/chassis_receipts     18/18 PASS  (receipts_test.exs)
core/chassis_inventory    25/25 PASS  (inventory_test.exs)
mix monorepo.compile --warnings-as-errors:   selected=1..4 / total=55  all green
```

The 50 untouched packages still ship generated marker + smoke tests
(`Chassis.Package.<Name>` + `package_smoke_test.exs`) classified as
`generated_skeleton` / `non_behavioral_test` in
`docs/implementation_notes/recovery_baseline.md`. They are scheduled for
deletion at each package's activating phase, per 0541 §2 item 2. These
50 smoke tests continue to pass under `mix blitz.workspace test` and do
not block any phase.

## Checklist items completed (canonical 0503)

* Phase 0: 17 items
* Phase 1: 15 items + 1 inline DEFERRED annotation (GroundPlane.Boundary.Codec dep → Phase 9)
* Phase 2: 16 items + 1 inline partial-DEFERRED annotation (AshPostgres backend → Phase 11/18)
* Phase 3: 13 items + 1 inline partial-DEFERRED annotation (dynamic-discovery HTTP clients → Phase 8)

Every box checked has a corresponding phase report under
`docs/implementation_notes/phase_NN_report.md` showing
failing-test → impl → passing-test evidence.

## Known gaps (already documented as DEFERRED inline + in phase reports)

1. `GroundPlane.Boundary.Codec` integration in `chassis_contracts` —
   deferred to Phase 9 (`chassis_boundary`) when the sibling-repo dep on
   `ground_plane_contracts` belongs. Byte-stable canonical encoding is
   already verified by `Chassis.Contracts.encode/1`.
2. `Chassis.Receipts.Store.AshPostgres` real backend — deferred until
   Postgres + Ash are added to `build_support/dependency_sources.config.exs`
   in Phases 11/18. Today the backend module returns
   `{:error, {:not_implemented, __MODULE__}}` from every callback.
3. `Chassis.Inventory.DynamicDiscovery.*` real HTTP clients — deferred to
   Phase 8 per 0537 §3. Today every provider returns
   `{:error, {:not_implemented, __MODULE__}}` and the facade returns
   `{:error, :missing_provider}` when no provider is supplied (no silent
   fall-through to the static fixture).
4. The 50 remaining generated `Chassis.Package.<Name>` marker modules and
   `package_smoke_test.exs` files survive in untouched packages. They will
   be removed and replaced with behavioral tests at each package's
   activating phase per 0541 §2 item 2.

Other suspicious-but-not-yet-active hot spots already filed in
`recovery_baseline.md` §9 (StackLab proof, AppKit profile:monolith,
Mezzanine outbox simulated dispatch, StackManager fictive
`receipt:deployment:smoke`) remain in place; each is hardened in its
activating phase (21, 16, 17, 11 respectively).

## Exact next phase

**Phase 4 — `chassis_core` + Engine.** Permitted package set:
* `core/chassis_core`

Permitted to depend on (already activated): `chassis_contracts`,
`chassis_receipts`, `chassis_inventory`. The Phase 4 checklist requires:

* `Chassis.Core.Engine` GenServer with state machine:
  `:offline → :provisioning → :booting → :healthy → :degraded → :failed → :recovering → :healthy`
* Fail-closed guard: no transition out of `:failed` without explicit
  `Chassis.Core.Engine.recover/1`
* `Chassis.Core.Dispatcher.dispatch/2` routes through
  `Chassis.Contracts.Adapter` callbacks
* `Chassis.Core.NodeRegistry` (ETS-backed) tracking node lifecycle events
  with timestamps
* State-machine property tests via `stream_data`
* Mock adapter for engine simulation tests
* Crash recovery test: kill the engine, restart, assert state is rehydrated
  from `chassis_receipts`
* Spine Audit: Engine never reaches into adapter internals
* QC Gate: `mix blitz.workspace.impact test --projects chassis_core`,
  `mix run -e '{:ok, _} = Chassis.Core.Engine.start_link([]); IO.inspect(Chassis.Core.Engine.state())'`

Test-first rhythm: write failing tests covering happy-path lifecycle,
fail-closed `:failed → :recovering` guard, dispatcher routes only through
`Chassis.Contracts.Adapter` (use a stub adapter that returns the canonical
not_implemented tuple), crash recovery via `chassis_receipts` rehydration,
and `NodeRegistry` ETS lifecycle tracking. Then implement.

When done, add a phase 4 report under
`docs/implementation_notes/phase_04_report.md` using the template in 0541 §8
and mark Phase 4 boxes progressively in
`/home/home/p/g/j/jido_brainstorm/nshkrdotcom/docs/20260529/chassis_impl/0503_implementation_checklist.md`.

## Permitted packages cheat-sheet for the next 5 phases (from 0537 §3)

* Phase 4: `core/chassis_core`
* Phase 5: `core/chassis_releases` + `adapters/chassis_local`
* Phase 6: `core/chassis_environments`
* Phase 7: `bootstrap/chassis_bootstrap` + `adapters/chassis_ssh`
* Phase 8: `adapters/chassis_tofu` + dynamic-discovery HTTP clients in `core/chassis_inventory`
