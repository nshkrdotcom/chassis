# Phase 22 Report - Evolution Contracts

Date: 2026-06-03

## Scope

- Permitted package: `evolution/chassis_evolution_contracts`.
- Source commit: `1a581deced35ecd8318c57307fe5b6e89545a60c`.
- Sibling repo bridge work: none.

## Implemented

- Added the canonical 18-state evolution state set and terminal-state truth
  table.
- Added `Chassis.Evolution.PromotionPreconditions` with all required authority,
  rollback, target, state-volume, and trace fields from the lifecycle spec.
- Implemented the Phase 22 DTO modules:
  `FailureBatch`, `CandidatePatch`, `CandidateImage`, `TrialRun`,
  `ScoreMatrix`, `PromotionIntent`, `PromotionReceipt`, `RollbackReceipt`,
  `OperatorConsent`, `CodeAgentRun`, and `StageArtifact`.
- Added DTO required-field metadata, `new!/1`, `to_json/1`, and `from_json/1`
  helpers with finite field normalization and typed casting for atoms,
  datetimes, atom lists, and bounded summary maps.
- Added exact behaviour callback contracts for `CodingAgentRunner`, `Scorer`,
  `TrialProvider`, and `PromotionExecutor`.
- Replaced the shallow package marker smoke test with contract tests that fail
  against bare structs or incorrect callbacks.

## Test-First Evidence

- Initial `mix test` failed because `PromotionPreconditions.required_fields/0`
  and `new!/1` were missing.
- Initial `mix test` failed because `CodingAgentRunner` lacked `cancel_run/2`.
- Initial `mix test` failed because DTO modules lacked `required_fields/0` and
  JSON round-trip helpers.
- The first implementation compile failed on invalid `with ... rescue` syntax in
  `from_json/5`; this was fixed with a proper `try/rescue`.
- A subsequent DTO round-trip test caught boolean JSON encoding as strings for
  `consent_required?`; boolean encoding now preserves JSON booleans.

## Verification

- `cd evolution/chassis_evolution_contracts && mix deps.get`: passed.
- `cd evolution/chassis_evolution_contracts && mix format --check-formatted`:
  passed.
- `cd evolution/chassis_evolution_contracts && mix test`: 4 tests, 0 failures.
- `cd evolution/chassis_evolution_contracts && mix run -e 'IO.inspect(Chassis.Evolution.States.all() |> length())'`:
  printed `18`.
- `cd evolution/chassis_evolution_contracts && mix deps.tree`: only
  `jason ~> 1.4`; no dependency on `chassis_core`, `chassis_boundary`,
  adapters, or product repos.
- `mix monorepo.compile --warnings-as-errors`: passed, selected 36 skipped 19
  total 55.
- `mix monorepo.test`: passed, selected 36 skipped 19 total 55.

## Failed / Deferred Checks

- `mix blitz.workspace.impact test --projects chassis_evolution_contracts`
  failed before execution with Blitz option parsing:
  `** (Mix) Invalid options: [{"--projects", nil}]`.
- `mix ci` failed at workspace format checks on pre-existing out-of-phase files
  outside `evolution/chassis_evolution_contracts`, including
  `core/chassis_inventory`, `core/chassis_mesh`, `core/chassis_receipts`,
  `core/chassis_stack`, `bootstrap/chassis_bootstrap`,
  `bootstrap/chassis_doctor`, `bootstrap/chassis_installer`,
  `adapters/chassis_artifact_fs`, and `adapters/chassis_systemd`.

## Generated Artifacts

- `_build/` and `deps/` were generated during package verification and are
  ignored/not committed.
- `.blitz/test_state_v1/indexes/task_states.ndjson` changed during CI and was
  restored before commits.
