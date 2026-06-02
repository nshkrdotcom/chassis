# Phase 5 Report — `chassis_stack` Virtual-to-Physical Mapping

## 1. Scope

* Permitted packages (per 0537 §3): `core/chassis_stack`.
* Files touched:
  * `core/chassis_stack/lib/chassis/stack.ex` (rewritten — capacity-aware
    PlacementPlanner that consults `Chassis.Inventory.PlacementValidator`;
    Composer now returns the adapter set inside the topology; strict
    `:unknown_environment` rejection for non-`:dev`/`:prod` envs;
    `:no_hosts` error when host list is empty)
  * `core/chassis_stack/mix.exs` (added path deps on chassis_contracts +
    chassis_inventory)
  * `core/chassis_stack/mix.lock` (new)
  * `core/chassis_stack/test/stack_test.exs` (new — 18 behavioral tests)
  * `core/chassis_stack/lib/chassis/package/chassis_stack.ex` (deleted)
  * `core/chassis_stack/test/package_smoke_test.exs` (deleted)

## 2. Test-First Evidence

* Failing test commit: `stack_test.exs` written first; initial run failed
  because the prior `PlacementPlanner.plan/2` blindly round-robin-assigned
  placements without consulting `Chassis.Inventory.PlacementValidator`, the
  `Composer` did not bubble up the resolved adapter set, and there was no
  `:unknown_environment` rejection.
* Passing commit: this Phase 5 commit; 18 behavioral tests, 0 failures.

## 3. Checklist Items Completed

- [x] Start-of-Phase Spine Audit (re-read 0505 §3-§4 placement architecture
  and confirmed no `case node()` branching is needed)
- [x] Progressive Checking
- [x] `Chassis.Stack.ConfigurationProfile` registry — all four canonical
  profiles (`monolith`, `decoupled-cockpit-2`, `ternary-split-3`,
  `maximal-decoupled`) as compile-time literals
- [x] `Chassis.Stack.ProfileResolver.resolve/2` returning the resolved map
  with dev/prod adapter sets; all 4×2=8 combos covered by tests
- [x] `Chassis.Stack.Composer` wiring placement → BEAM node → physical host
  through `compose/3`; returns full topology map
- [x] `Chassis.Stack.PlacementPlanner` choosing which host runs which BEAM
  node per profile — capacity-aware via
  `Chassis.Inventory.PlacementValidator.check/2`; rejects
  `:insufficient_capacity` and `:no_hosts`
- [x] Unit tests: each profile × dev/prod resolves to expected adapter set
- [x] Spine Audit: `Atom.to_string |> String.starts_with?` pattern
  invariant verified (every `node_name_pattern` matches `^[a-z_]+@\*$`,
  and there is no `case node()` branching outside the moduledoc example)
- [x] QC Gate: 18 tests pass; `mix monorepo.compile --warnings-as-errors`
  green (selected=7/55); static-CLI regressions remain 12/12 + 6/6

## 4. Checklist Items Deferred

None for Phase 5.

## 5. Execution Integrity Audit Output

```text
=== unsupported success in core/chassis_stack/lib === (empty)
=== shallow tests === (empty)
=== case node() branching in implementation === (empty after moduledoc strip)
=== generator / bulk markers === (empty)
```

## 6. Cross-Phase Invariants

* I1 PASS — only `core/chassis_stack` touched
* I2 PASS — 12/12 + 6/6 static-CLI tests still green
* I3 PASS — pre-existing marker deleted; no new ones
* I4 PASS — no `*_generator.exs`
* I5 PASS — line-by-line checklist edits (next commit)
* I6 PASS — 18 tests across registry shape, dev/prod adapter resolution,
  capacity-aware placement fitting + over-commit refusal, end-to-end
  Composer, and spine-audit guards
* I7 N/A — no receipt types added in Phase 5
* I8 N/A — Composer does not mutate; tenant context propagation lands
  alongside `chassis_releases` (Phase 11) and `chassis_tenant` (Phase 19)

## 7. QC Gate Output

```text
$ (cd core/chassis_stack && mix test --warnings-as-errors)
18 tests, 0 failures

$ mix monorepo.compile --warnings-as-errors
Blitz impact summary: selected=7 skipped=48 total=55

$ (cd manager/chassis_cli && mix test)
12 tests, 0 failures

$ mix test  # workspace root
6 tests, 0 failures
```

## 8. Commits And Push Status

* `~/p/g/n/chassis`: this commit. **Push pending until end of run.**

## 9. Handoff

Not rotating. Continuing into Phase 6 if budget permits.
