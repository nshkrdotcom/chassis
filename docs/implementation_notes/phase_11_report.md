# Phase 11 Report — AppRegistry + StackManager

## 1. Scope

* Permitted packages (per 0537 §3): `core/chassis_releases`,
  `manager/chassis_stack_manager`.
* Files touched:
  * `core/chassis_releases/lib/chassis/releases.ex` — real release bundle
    materializer, `Chassis.AppRegistry.Entry`, backend behaviour, ETS
    backend, AshPostgres future adapter, and GenServer registry.
  * `manager/chassis_stack_manager/lib/chassis/stack_manager.ex` — real
    deployment transaction path, in-memory fence store, checkpoint store,
    and rollback path.
  * `manager/chassis_stack_manager/mix.exs` — path deps for active package
    logic plus sibling `ground_plane_contracts`.
  * `manager/chassis_stack_manager/mix.lock` — package-local lock.
  * Generated marker modules and generated smoke tests deleted for both
    activated packages.
  * Behavioral tests added for both packages.

## 2. Test-First Evidence

* Failing tests were written before implementation and replaced smoke tests.
* Initial failures:
  * `chassis_releases`: missing AppRegistry GenServer child spec,
    `Entry.new/1`, `Entry.new!/1`, `Bundle.materialize/2`,
    `active_profile/2`, backend `init/1`/`put/2`/`get/2`/`list/2`/`delete/2`.
  * `chassis_stack_manager`: missing `Chassis.AppRegistry.Entry` dependency
    and static transaction return shape.
* Passing result:
  * `core/chassis_releases`: 5 tests, 0 failures.
  * `manager/chassis_stack_manager`: 4 tests, 0 failures.

## 3. Checklist Items Completed

- [x] Start-of-Phase Spine Audit — reviewed 0503 Phase 11, 0506, 0520,
  0537, and current package map drift.
- [x] Progressive Checking.
- [x] `Chassis.AppRegistry` GenServer per 0506 §1.
- [x] `Chassis.AppRegistry.Backend.Ets` default backend.
- [x] Behavioral QC assertions for GenServer state, deployed app
  registration, rollback pointer behavior, concurrent registration, and
  duplicate app_ref conflict resolution.
- [x] `Chassis.AppRegistry.Backend.AshPostgres` explicit future adapter
  returning `{:error, {:not_implemented, __MODULE__}}`.
- [x] `Chassis.AppRegistry.Entry` typed struct with the 14 fields from
  0506 §1. The checklist says 13 fields, but the spec table lists 14.
- [x] `Chassis.Releases.Bundle` materializer + SHA-256 validation.
- [x] `Chassis.StackManager.Transaction.run/1` orchestrates:
  fence acquire, resolve profile, discover hosts, validate topology,
  authorize, provision, mesh join, register app, emit receipt.
- [x] Idempotency via a `GroundPlane.Contracts.Fence`-shaped fence and
  `Chassis.StackManager.FenceStore`.
- [x] Rollback via `GroundPlane.Contracts.Checkpoint` and
  `Chassis.StackManager.CheckpointStore`.
- [x] End-to-end test registers two deployments, lists/looks up via
  AppRegistry, rolls back one, and asserts the receipt chain.
- [x] Spine Audit: registry is the single source of truth for
  `active_profile`; tests assert `AppRegistry.active_profile/2`.

## 4. Checklist Items Deferred

* DEFERRED: CLI smoke commands (`mix chassis.stack.deploy`,
  `mix chassis.app.list`) remain Phase 20 work. Phase 11 package map does
  not permit mutating `manager/chassis_cli`; static CLI regressions remain
  green and no static success path was introduced.

## 5. Execution Integrity Audit Output

```text
$ rg -n "implemented\?\(\)|package_smoke_test|receipt:deployment:smoke|checkpoint:smoke|rollback:smoke|\{:ok, %\{status: :active|defdelegate .*AshPostgres" core/chassis_releases manager/chassis_stack_manager
manager/chassis_stack_manager/test/stack_manager_test.exs:65: refute result.receipt_ref == "receipt:deployment:smoke"
```

## 6. Cross-Phase Invariants

* I1 PASS — source changes limited to the two Phase 11 packages and this
  report.
* I2 PASS — 12/12 manager CLI static-invariant tests + 6/6 workspace-root
  CLI static-invariant tests still green.
* I3 PASS — generated marker modules and smoke tests deleted for both
  activated packages.
* I4 PASS — no generator scripts added.
* I5 PASS — checklist edits are line-level and tied to completed work.
* I6 PASS — 9 behavioral tests cover happy paths, unhappy paths,
  concurrency, duplicate conflict resolution, fail-closed authority,
  idempotency, registry side effects, receipts, rollback checkpoints, and
  explicit future-adapter behavior.
* I7 PASS — no secret material handling added.
* I8 PASS — no failed/incomplete artifact pointer is promoted; idempotent
  replay returns the stored completed result.

## 7. QC Gate Output

```text
$ (cd core/chassis_releases && mix test)
5 tests, 0 failures

$ (cd manager/chassis_stack_manager && mix test)
4 tests, 0 failures

$ (cd core/chassis_releases && mix format --check-formatted)
ok

$ (cd manager/chassis_stack_manager && mix format --check-formatted)
ok

$ mix monorepo.compile --warnings-as-errors
Blitz impact summary: selected=24 skipped=31 total=55

$ mix blitz.workspace.impact test
Blitz impact summary: selected=24 skipped=31 total=55

$ mix test test/root_cli_static_response_path_regression_test.exs
6 tests, 0 failures

$ (cd manager/chassis_cli && mix test test/static_response_path_regression_test.exs)
12 tests, 0 failures
```

## 8. Commits And Push Status

* `~/p/g/n/chassis`: this commit. Push pending until end of phase.
* `~/p/g/j/jido_brainstorm/nshkrdotcom`: checklist commit follows after
  source commit.
