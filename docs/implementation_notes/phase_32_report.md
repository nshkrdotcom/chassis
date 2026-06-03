# Phase 32 Report - State-Preserving Swap Supervisor

Date: 2026-06-03

## Scope

- Package map scope: `host/chassis_swap_supervisor`.
- Existing package changed: `host/chassis_swap_supervisor`.
- Source commit: `82f2389a7b49b77172e76dc879b2d6671418f9dd`.
- Sibling repo bridge work: none.
- `core/chassis_releases` was not changed because Phase 32 package-map scope
  permits only `host/chassis_swap_supervisor`. The swap supervisor consumes the
  existing `Chassis.Releases.ApprovedMounts.list/2` path dependency.

## Implemented

- Replaced generated static `promote/2` and rollback responses with a real
  `Chassis.Evolution.PromotionExecutor` implementation.
- Added `execute_swap/2`, `start_swap/2`, `promote/2`, `rollback_swap/2`,
  `rollback/2`, and `start_swap_task/2`.
- Added pre-flight validation for required `PromotionPreconditions` fields and
  `regression_gate: :passed`.
- Added approved mutable mount validation through
  `Chassis.Releases.ApprovedMounts.list/2` or an injected provider; mismatched
  kinds, unapproved paths, and invalid allowlist data fail closed.
- Added deterministic swap refs plus explicit `swap_ref` support.
- Added `Chassis.Swap.Supervisor.IdempotencyTable` so replayed `swap_ref`
  requests return the cached result without re-running side effects.
- Added ordered host transition orchestration: capture current artifact,
  stop active service, switch artifact/mount context, start target service.
- Added rollback orchestration that restores the captured prior artifact when a
  post-capture transition fails.
- Added package-local smoke command:
  `mix chassis.host.swap --candidate-ref <ref> --json`.

## Test-First Evidence

- Initial Phase 32 tests failed because `execute_swap/2` was undefined and
  `Chassis.Swap.Supervisor.IdempotencyTable` did not exist.
- The first implementation passed the core tests but a new fail-closed test for
  invalid allowlist provider output failed with a `Protocol.UndefinedError`;
  allowlist normalization was then changed to return a structured error.
- Final tests cover missing required preconditions, mount-kind mismatch,
  unapproved paths, invalid allowlist data, pre-stop prior artifact capture,
  idempotent replay, and rollback after switch failure.

## Verification

- `cd host/chassis_swap_supervisor && mix deps.get`: passed.
- `cd host/chassis_swap_supervisor && mix format --check-formatted`: passed.
- `cd host/chassis_swap_supervisor && mix compile --warnings-as-errors`: passed.
- `cd host/chassis_swap_supervisor && mix test`: 7 tests, 0 failures.
- `cd host/chassis_swap_supervisor && mix deps.tree`: dependency tree includes
  `chassis_evolution_contracts`, `chassis_releases`, and `jason`.
- Direct smoke:
  `cd host/chassis_swap_supervisor && mix chassis.host.swap --candidate-ref cand:dev:smoke --json | jq -r '.swap_ref'`
  returned `swap:cand:dev:smoke`.
- Grep audit for `execute_swap`, `IdempotencyTable`, `ApprovedMounts`,
  `mount_kind_mismatch`, `unapproved_mount_path`, `prior_artifact_digest`,
  `rollback_swap`, `rollback_fun`, and `chassis.host.swap` showed the checks in
  the swap supervisor source, tests, and package-local Mix task.
- `mix monorepo.compile --warnings-as-errors`: passed, selected 47 skipped 8
  total 55.
- `mix monorepo.test`: passed, selected 47 skipped 8 total 55.

## Failed / Deferred Checks

- `mix blitz.workspace.impact test --projects chassis_swap_supervisor` failed
  before execution with Blitz option parsing:
  `** (Mix) Invalid options: [{"--projects", nil}]`.
- `mix ci` failed during workspace format checks on pre-existing out-of-phase
  formatting drift outside Phase 32. `host/chassis_swap_supervisor` passed its
  package-local format, compile, tests, and smoke checks, and passed the CI
  format stage before unrelated failures completed.
- Exact manager-binary smoke
  `./chassis host.swap --candidate-ref cand:dev:smoke --json | jq '.swap_ref'`
  is deferred because post-Phase-20 CLI extension is package-local/disabled. The
  package-local Mix task smoke used real package logic and returned the swap ref.
- `core/chassis_releases` allowlist changes are deferred because that package is
  outside Phase 32 package-map scope; the existing allowlist module is consumed.

## Generated Artifacts

- `_build/` and `deps/` were generated during verification and are ignored/not
  committed.
- `.blitz/test_state_v1/indexes/task_states.ndjson` changed during monorepo/CI
  commands and was restored before commits.
