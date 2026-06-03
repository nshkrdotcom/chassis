# Phase 33 Report - Health Probe and Rollback

Date: 2026-06-03

## Scope

- Package map scope: `host/chassis_health_probe`.
- Existing package changed: `host/chassis_health_probe`.
- Source commit: `fc82c0fa68c1dd2d8ae1c1d3c7b2aa34b0763b65`.
- Sibling repo bridge work: none.

## Implemented

- Replaced the generated `force`-based static probe stub with a real synchronous
  probe engine and GenServer facade.
- Added default policy: `window_ms: 90_000`, `interval_ms: 5_000`,
  `consecutive_required: 3`, `rollback_on_failure?: true`, and the eight
  required check atoms.
- Added check modules for `:http_health`, `:beam_alive`, `:mesh_connectivity`,
  `:appkit_readback`, `:mezzanine_heartbeat`, `:citadel_smoke`,
  `:state_heartbeat`, and `:model_runtime_health`.
- Added probe tick evaluation, consecutive-success commit, timeout rollback, and
  hard-failure rollback.
- Added rollback dispatch through `Chassis.Swap.Supervisor.rollback_swap/2`, with
  test/runtime injection support for host-side side effects.
- Added double-fault handling that emits a critical `HealthSignal` through
  `Chassis.Metrics.emit_health_signal/2`.
- Added `Chassis.Health.Probe.Supervisor` and `Chassis.Health.Probe.Registry`.
- Added package-local smoke command:
  `mix chassis.host.probe --swap-ref <ref> --json`.

## Test-First Evidence

- Initial Phase 33 tests failed because `default_policy/0` was undefined and the
  generated `run/2` always returned a static committed/rolled-back payload
  without check execution, rollback dispatch, timeout handling, or observability.
- Final tests cover default policy, successful commit after three consecutive
  ticks, forced check failure rollback, timeout rollback, and rollback double
  fault with critical `HealthSignal` emission.

## Verification

- `cd host/chassis_health_probe && mix deps.get`: passed.
- `cd host/chassis_health_probe && mix format --check-formatted`: passed.
- `cd host/chassis_health_probe && mix compile --warnings-as-errors`: passed.
- `cd host/chassis_health_probe && mix test`: 5 tests, 0 failures.
- `cd host/chassis_health_probe && mix deps.tree`: dependency tree includes
  `chassis_evolution_contracts`, `chassis_mesh`, `chassis_aitrace_bridge`,
  `chassis_metrics`, `chassis_swap_supervisor`, and `jason`.
- Direct smoke:
  `cd host/chassis_health_probe && mix chassis.host.probe --swap-ref swap:dev:smoke --json | jq -r '.outcome'`
  returned `committed`.
- Grep audit for `default_policy`, `window_ms`, `interval_ms`,
  `consecutive_required`, `rollback_swap`, `rolled_back_failed`,
  `rollback_failed`, `severity: :critical`, `emit_health_signal`,
  `Probe.Check`, `chassis.host.probe`, and `probe_timeout` showed the checks in
  health probe source, tests, and Mix task.
- `mix monorepo.compile --warnings-as-errors`: passed, selected 48 skipped 7
  total 55.
- `mix monorepo.test`: passed, selected 48 skipped 7 total 55.

## Failed / Deferred Checks

- `mix blitz.workspace.impact test --projects chassis_health_probe` failed
  before execution with Blitz option parsing:
  `** (Mix) Invalid options: [{"--projects", nil}]`.
- `mix ci` failed during workspace format checks on pre-existing out-of-phase
  formatting drift outside Phase 33. `host/chassis_health_probe` passed its
  package-local checks and its CI format stage before unrelated failures
  completed.
- Exact manager-binary smoke
  `./chassis host.probe --swap-ref swap:dev:smoke --json | jq '.outcome'`
  is deferred because post-Phase-20 CLI extension is package-local/disabled. The
  package-local Mix task smoke used real package logic and returned `committed`.

## Generated Artifacts

- `_build/` and `deps/` were generated during verification and are ignored/not
  committed.
- `.blitz/test_state_v1/indexes/task_states.ndjson` changed during monorepo/CI
  commands and was restored before commits.
