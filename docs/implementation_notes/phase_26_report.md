# Phase 26 Report - Trial Runtime Isolation

Date: 2026-06-03

## Scope

- Checklist package: `evolution/chassis_trial_runtime`.
- Package-map permitted packages: `evolution/chassis_trial_runtime`,
  `host/chassis_trial_supervisor`.
- Source commit: `49cd9c30aceac88f00265903b25ef11fa3836f6c`.
- Sibling repo bridge work: none.

## Implemented

- Replaced generated smoke tests with behavior tests for isolated trial
  lifecycle, state-mount rejection, teardown, provider contract behavior, and
  package-local CLI JSON output.
- Implemented `Chassis.Trial.IsolationProfile` with unique BEAM node names,
  cookie refs, port ranges, and production state mount overlap validation.
- Implemented `Chassis.Trial.Runtime` as the
  `Chassis.Evolution.TrialProvider` facade.
- Added isolated Phase 26 providers
  `Chassis.Trial.Provider.{Fixture, Container, Systemd, SSH}`. Container,
  systemd, and SSH use the same isolated lifecycle contract in this phase;
  external materialization is deferred to Phase 27.
- Implemented `Chassis.Trial.Supervisor` as an Agent-backed lifecycle store for
  candidate image metadata, active trial records, teardown, and replay-safe
  lookup.
- Added package-local `mix chassis.node.trial` task for `fixture`, `container`,
  `systemd`, and `ssh` provider selection with structural JSON output.

## Test-First Evidence

- Initial `chassis_trial_runtime` tests failed because
  `Runtime.provision_trial/3`, `Runtime.teardown_trial/1`,
  `IsolationProfile.default/1`, `IsolationProfile.validate_mounts/2`,
  `Mix.Tasks.Chassis.Node.Trial`, DTO wiring, and `Jason` dependency wiring were
  absent.
- Initial `chassis_trial_supervisor` tests failed because there was no process
  lifecycle store and no arity-2 build/start/stop functions.
- After implementation, the focused tests assert behavior that static success
  payloads cannot satisfy: collision-resistant identities, persisted active
  trial records, teardown removal, closed mount rejection, and JSON emitted from
  real package code.

## Verification

- `cd evolution/chassis_trial_runtime && mix deps.get`: passed.
- `cd host/chassis_trial_supervisor && mix format --check-formatted`: passed.
- `cd host/chassis_trial_supervisor && mix test`: 2 tests, 0 failures.
- `cd evolution/chassis_trial_runtime && mix format --check-formatted`: passed.
- `cd evolution/chassis_trial_runtime && mix test`: 6 tests, 0 failures.
- `cd evolution/chassis_trial_runtime && mix deps.tree`: dependencies are
  `chassis_evolution_contracts`, `chassis_trial_supervisor`, and `jason`.
- `cd host/chassis_trial_supervisor && mix deps.tree`: no runtime package
  dependencies.
- `cd evolution/chassis_trial_runtime && mix compile --quiet && mix chassis.node.trial --candidate-ref cand:dev:smoke --diff-path test/fixtures/empty.patch --kind fixture --json | jq '.trial_ref'`:
  returned a `trial:cand:dev:smoke:*` ref.
- `mix monorepo.compile --warnings-as-errors`: passed.
- `mix monorepo.test`: passed, selected 42 skipped 13 total 55.

## Failed / Deferred Checks

- `mix blitz.workspace.impact test --projects chassis_trial_runtime,chassis_trial_supervisor`
  failed before execution with Blitz option parsing:
  `** (Mix) Invalid options: [{"--projects", nil}]`.
- Exact manager-binary smoke command is deferred because post-Phase-20 CLI
  extension is package-local; the package-local `mix chassis.node.trial` smoke
  passed and dispatches through `Chassis.Trial.Runtime`.
- `mix ci` failed during workspace format checks on pre-existing out-of-phase
  files outside Phase 26, including `bootstrap/chassis_bootstrap`,
  `bootstrap/chassis_doctor`, `bootstrap/chassis_installer`,
  `core/chassis_mesh`, `core/chassis_receipts`, `core/chassis_stack`,
  `adapters/chassis_artifact_fs`, and `adapters/chassis_systemd`.

## Generated Artifacts

- `_build/` and `deps/` were generated during package verification and are
  ignored/not committed.
- `.blitz/test_state_v1/indexes/task_states.ndjson` changed during CI and was
  restored before commits.
