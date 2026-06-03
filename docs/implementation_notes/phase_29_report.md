# Phase 29 Report - Evolution Core State Machine

Date: 2026-06-03

## Scope

- Permitted package: `evolution/chassis_evolution_core`.
- Source commit: `32abdc39922da6f7fa14a4e0428b643bf1f3d025`.
- Sibling repo bridge work: none.

## Implemented

- Replaced generated smoke coverage with state-machine tests for every declared
  legal transition, illegal transition rejection, promotion preconditions,
  receipt-backed recovery, registry listing, and package-local CLI output.
- Implemented `Chassis.Evolution.Core.TransitionReceipt` and
  `Chassis.Evolution.Core.ReceiptLog` for transition receipt capture and
  rehydration.
- Implemented `Chassis.Evolution.Core` GenServer status, transition metadata,
  terminal-state rejection, promotion precondition enforcement, stop handling,
  and JSON-safe status projection.
- Implemented `Chassis.Evolution.Registry` as an Agent-backed active-run
  registry.
- Added package-local tasks `mix chassis.evolution.start`,
  `mix chassis.evolution.status`, and `mix chassis.evolution.stop`.

## Test-First Evidence

- Initial tests failed because the package lacked dependencies on evolution
  contracts and `Jason`, had no receipt log, no transition arity carrying
  metadata, no registry process, no package-local tasks, and illegal transitions
  returned only a generic atom.
- The final tests exercise all transition table edges, every terminal rejection
  path, missing/blocked promotion preconditions, receipt-backed crash recovery,
  registry side effects, and start-task JSON generated from the GenServer state.

## Verification

- `cd evolution/chassis_evolution_core && mix deps.get`: passed.
- `cd evolution/chassis_evolution_core && mix format --check-formatted`: passed.
- `cd evolution/chassis_evolution_core && mix test`: 7 tests, 0 failures.
- `cd evolution/chassis_evolution_core && mix deps.tree`: dependencies are
  `chassis_evolution_contracts` and `jason`.
- `cd evolution/chassis_evolution_core && mix compile --quiet && mix chassis.evolution.start --batch-ref fb:dev:smoke --json | jq '.state'`:
  returned `"queued"`.
- `mix chassis.evolution.status --json | jq '.state'`: returned `"queued"`.
- `mix chassis.evolution.stop --evolution-ref evo:dev:smoke --json | jq '.state'`:
  returned `"stopped"`.
- Adapter-import grep against `evolution/chassis_evolution_core/lib` and tests
  returned no matches for container, trial runtime, scoring, coding-agent, host,
  or swap adapter modules.
- `mix monorepo.compile --warnings-as-errors`: passed.
- `mix monorepo.test`: passed, selected 45 skipped 10 total 55.

## Failed / Deferred Checks

- `mix blitz.workspace.impact test --projects chassis_evolution_core` failed
  before execution with Blitz option parsing:
  `** (Mix) Invalid options: [{"--projects", nil}]`.
- Exact manager-binary smoke command is deferred because post-Phase-20 CLI
  extension is package-local; all three package-local Mix task smokes passed.
- `mix ci` failed during workspace format checks on pre-existing out-of-phase
  files and dependency directories outside Phase 29.

## Generated Artifacts

- `_build/` and `deps/` were generated during package verification and are
  ignored/not committed.
- `.blitz/test_state_v1/indexes/task_states.ndjson` changed during CI and was
  restored before commits.
