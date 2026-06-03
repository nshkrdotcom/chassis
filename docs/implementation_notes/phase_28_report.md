# Phase 28 Report - Candidate Scoring Gate

Date: 2026-06-03

## Scope

- Checklist packages: `evolution/chassis_candidate_scoring`,
  `evolution/chassis_evolution_receipts` for `ScoreMatrixRecord`.
- Package-map permitted package: `evolution/chassis_candidate_scoring`.
- Source commit: `c3660b2c0b61e062e7892c120315cc041905aafc`.
- Sibling repo bridge work: none.

## Implemented

- Replaced static score payload logic with `Chassis.Candidate.Scoring` as a
  `Chassis.Evolution.Scorer` behaviour implementation.
- Added behaviour-based delegation to a supplied scorer adapter, with a
  deterministic `FixtureScorer` adapter for local smoke and package task use.
- Implemented regression gate rules:
  `:baseline_regression`, `:confidence_below_threshold`, and
  `:evidence_subset_failed`.
- Enforced `blocked_reasons` as a closed set.
- Added optional score-matrix receipt recording through the existing
  `Chassis.Evolution.Receipts.ScoreMatrixRecord` and memory receipt store,
  without modifying the receipts package.
- Added package-local `mix chassis.evolution.score.show --candidate-ref <ref>`
  JSON output.

## Test-First Evidence

- Initial tests failed because the package lacked dependencies on evolution DTOs,
  receipt records, `Jason`, `score_trial/2`, and the package-local Mix task.
- The replacement tests require scorer behaviour delegation, adapter call
  evidence, baseline regression blocking, low-confidence blocking, required
  evidence subset blocking, closed-set blocked reasons, receipt-store
  side-effects, and JSON task output.

## Verification

- `cd evolution/chassis_candidate_scoring && mix deps.get`: passed.
- `cd evolution/chassis_candidate_scoring && mix format --check-formatted`:
  passed.
- `cd evolution/chassis_candidate_scoring && mix test`: 7 tests, 0 failures.
- `cd evolution/chassis_candidate_scoring && mix deps.tree`: dependencies are
  `chassis_evolution_contracts`, `chassis_evolution_receipts`, and `jason`.
- `cd evolution/chassis_candidate_scoring && mix compile --quiet && mix chassis.evolution.score.show --candidate-ref cand:dev:smoke --json | jq '.regression_gate'`:
  returned `"passed"`.
- Behaviour grep showed only `@behaviour Chassis.Evolution.Scorer` modules and
  `scorer.score_trial/2`; no StackLab or ExecutionPlane imports.
- `mix monorepo.compile --warnings-as-errors`: passed.
- `mix monorepo.test`: passed, selected 44 skipped 11 total 55.

## Failed / Deferred Checks

- `mix blitz.workspace.impact test --projects chassis_candidate_scoring` failed
  before execution with Blitz option parsing:
  `** (Mix) Invalid options: [{"--projects", nil}]`.
- Exact manager-binary smoke command is deferred because post-Phase-20 CLI
  extension is package-local; `mix chassis.evolution.score.show ... --json`
  passed and dispatches through real scoring logic.
- Direct edits to `evolution/chassis_evolution_receipts` are deferred because
  the package map restricts Phase 28 writes to `chassis_candidate_scoring`. The
  existing `ScoreMatrixRecord` is consumed successfully.
- `mix ci` failed during workspace format checks on pre-existing out-of-phase
  files and dependency directories outside Phase 28.

## Generated Artifacts

- `_build/` and `deps/` were generated during package verification and are
  ignored/not committed.
- `.blitz/test_state_v1/indexes/task_states.ndjson` changed during CI and was
  restored before commits.
