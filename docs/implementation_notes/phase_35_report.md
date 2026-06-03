# Phase 35 Report - Mezzanine Evolution Workflows

Date: 2026-06-03

## Scope

- Package map scope: integrations, no new Chassis leaf package.
- Chassis packages changed:
  - `governance/chassis_mezzanine_bridge`
  - `evolution/chassis_evolution_receipts`
- Sibling repo bridge work: `/home/home/p/g/n/mezzanine`.
- Chassis source commit: `038a446aaad081f86faa42435b7ccb1a2636d02d`, pushed.
- Mezzanine bridge commit: `9b031fca94bff448a438e768aa70c2e744f1c6df`, pushed.

## Implemented

- Added typed `Chassis.Mezzanine.Bridge.Outbox.Entry` rows carrying
  projection, primary ref, bounded payload, trace, tenant, installation,
  correlation, idempotency, and delivery status metadata.
- Added bridge-local evolution protocol dispatch for Phase 35 refs:
  failure batch, evolution start/stop/status, trial provision/replay,
  candidate scoring, promotion request/apply/rollback, model materialization,
  tensor reload, and tensor rollback.
- Added Chassis-side receipt-backed evolution boundary logic for failure batch,
  candidate patch, trial replay, scoring, promotion, swap, and rollback events.
- Added receipt projection hooks in `chassis_evolution_receipts` that emit
  bounded Mezzanine projection events per receipt kind.
- Replaced Mezzanine evolution placeholders with nine workflow modules under
  `Mezzanine.Workflow.Chassis.Evolution.*`.
- Added Mezzanine truth record structs for evolution intent, failure batch
  intent, candidate promotion intent, operator consent, model materialization,
  and tensor reload.
- Added Mezzanine evolution read projection storage with memory and temp-file
  backends plus facades for candidate, trial, score matrix, promotion, swap,
  model materialization, and tensor reload projections.
- Added Mezzanine workflow/read Mix task support for:
  - `mix mezzanine.workflow.dispatch chassis_failure_batch ...`
  - `mix mezzanine.read.get chassis_evolution --last 1`
- Added idempotency derivation from
  `sha256(workflow_id||step_id||input_digest)`.

## Test-First Evidence

- Initial Chassis bridge test failed because
  `Chassis.Mezzanine.Bridge.Outbox.Entry` was undefined.
- Initial evolution receipt test failed because
  `Chassis.Evolution.Receipts.AfterActions.projection_hook/1` was undefined.
- Initial Mezzanine bridge tests failed because evolution workflows,
  `ChassisEvolutionProjection`, `Engine`, and the local evolution dispatcher
  were still placeholders or missing.
- Final tests assert boundary dispatch per workflow, projection reduction,
  unhappy-path drain retry behavior, consent timeout stopping, idempotency
  derivation, and redaction of raw fields before projection/outbox storage.

## Sibling Repo Bridge Work

- Repo path: `/home/home/p/g/n/mezzanine`.
- Files changed:
  - `bridges/mezzanine_chassis_bridge/lib/mezzanine/workflow/chassis_workflows.ex`
  - `bridges/mezzanine_chassis_bridge/test/chassis_workflows_test.exs`
  - `lib/mix/tasks/mezzanine.read.get.ex`
  - `lib/mix/tasks/mezzanine.workflow.dispatch.ex`
- Tests run in sibling repo:
  - `cd bridges/mezzanine_chassis_bridge && mix format`: passed.
  - `cd bridges/mezzanine_chassis_bridge && mix compile --warnings-as-errors`: passed.
  - `cd bridges/mezzanine_chassis_bridge && mix test`: 8 tests, 0 failures.
  - `cd bridges/mezzanine_chassis_bridge && mix credo --strict`: passed.
  - `cd /home/home/p/g/n/mezzanine && mix mezzanine.workflow.dispatch chassis_failure_batch --tenant tenant:dev --installation installation:dev --evidence ev:smoke:1 --summary smoke`: passed.
  - `cd /home/home/p/g/n/mezzanine && mix mezzanine.read.get chassis_evolution --last 1`: passed.
  - `cd /home/home/p/g/n/mezzanine && mix ci`: after fixing Credo issues, visible stages passed through deps, format, compile, tests, strict Credo, Dialyzer, and docs; after docs the BEAM process remained idle with no child process or output for multiple polling intervals and was terminated with SIGTERM. The session reported exit code 0 with a SIGTERM notice, but no natural command completion line was observed.
- Commit hash: `9b031fca94bff448a438e768aa70c2e744f1c6df`, pushed.

## Verification

- `cd governance/chassis_mezzanine_bridge && mix format`: passed.
- `cd governance/chassis_mezzanine_bridge && mix compile --warnings-as-errors`: passed.
- `cd governance/chassis_mezzanine_bridge && mix test`: 7 tests, 0 failures.
- `cd evolution/chassis_evolution_receipts && mix format`: passed.
- `cd evolution/chassis_evolution_receipts && mix compile --warnings-as-errors`: passed.
- `cd evolution/chassis_evolution_receipts && mix test`: 8 tests, 0 failures.
- `cd /home/home/p/g/n/chassis && mix monorepo.compile --warnings-as-errors`: passed, selected 48 skipped 7 total 55.
- Required Chassis impact command:
  `mix blitz.workspace.impact test --projects chassis_mezzanine_bridge,chassis_evolution_receipts`
  failed before execution with Blitz option parsing:
  `** (Mix) Invalid options: [{"--projects", nil}]`.
- Mezzanine spine grep:
  `rg -n "Docker|docker|systemd|ssh|SSH|Host\\.Daemon|host_daemon|swap_candidate|rollback_swap" ...`
  returned zero matches.

## Failed / Deferred Checks

- Required Blitz impact `--projects` command still fails at option parsing
  before tests execute. Focused package tests and monorepo compile were used for
  verification.
- Final Mezzanine `mix ci` did not present a natural completion line after all
  visible stages passed through docs. The idle BEAM tail was terminated to avoid
  leaving a running session; this is recorded as a CI tail gap, not a package
  test failure.
- Core `Chassis.Boundary.Registry` was not modified because Phase 35 permits no
  new package changes. Evolution boundary refs use a bridge-local dispatcher for
  this integration phase.

## Generated Artifacts

- `_build/`, `deps/`, `doc/`, and temp projection files were generated during
  verification and are ignored/not committed.
- `.blitz/test_state_v1/indexes/task_states.ndjson` changed during Chassis and
  Mezzanine verification and was restored before commits.
