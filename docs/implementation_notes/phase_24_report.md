# Phase 24 Report - Candidate Registry and Evolution Receipts

Date: 2026-06-03

## Scope

- Permitted packages: `evolution/chassis_candidate_registry` and
  `evolution/chassis_evolution_receipts`.
- Source commit: `82734bf32245164a524273141493d0e0386be3cf`.
- Sibling repo bridge work: none.

## Implemented

- Replaced the candidate registry package marker with behavioral tests.
- Added the full `Chassis.Candidate.Registry.Entry` lifecycle field set and
  finite required-field validation.
- Implemented `register/2`, `update_state/3`, `attach_digest/4`,
  `attach_score_matrix/3`, `attach_authority/3`, `attach_consent/3`,
  `attach_swap/3`, `attach_rollback/3`, `get/2`, `list/1`, `fixture/0`, and
  JSON projection.
- Added Agent-backed candidate `Store.Memory` plus an `AshPostgres` facade that
  asserts the same entry schema and store behavior in-process for Phase 24.
- Added package-local `mix chassis.evolution.candidate.show --candidate-ref`.
- Extended evolution receipts from the Phase 23 `FailureBatchRecord` to the
  Phase 24 lifecycle records:
  `CandidatePatchRecord`, `CodingAgentRunRecord`, `TrialRunRecord`,
  `ScoreMatrixRecord`, `PromotionIntentRecord`, `PromotionRecord`,
  `SwapRecord`, `EvolutionRollbackRecord`, `OperatorConsentRecord`,
  `EvolutionStartRecord`, and `EvolutionStopRecord`.
- Added receipt required-field metadata, redacted constructors, memory-store
  kind filters, AshPostgres parity facade, and AITrace/Observability/
  Mezzanine/AppKit after-action stubs.

## Test-First Evidence

- Initial `chassis_evolution_receipts` tests failed because lifecycle receipt
  constructors, `required_fields/0`, after-action recorder/stubs, and
  `Store.AshPostgres.start_link/1` were missing.
- Initial `chassis_candidate_registry` tests failed at compile time because
  `CandidatePatchRecord` was still a future placeholder and the candidate
  package had no receipt dependency wiring.
- Candidate tests then caught an implementation warning in `attach_digest/4`
  default-argument clauses; this was fixed before monorepo
  `--warnings-as-errors`.
- Store parity tests caught a test normalization issue; the test now compares
  backend behavior with candidate refs normalized out.

## Verification

- `cd evolution/chassis_candidate_registry && mix deps.get`: passed.
- `cd evolution/chassis_evolution_receipts && mix format --check-formatted`:
  passed.
- `cd evolution/chassis_candidate_registry && mix format --check-formatted`:
  passed.
- `cd evolution/chassis_evolution_receipts && mix test`: 5 tests, 0 failures.
- `cd evolution/chassis_candidate_registry && mix test`: 3 tests, 0 failures.
- `cd evolution/chassis_candidate_registry && mix run -e 'Chassis.Candidate.Registry.list(tenant_ref: "tenant:dev") |> IO.inspect()'`:
  printed `[]` for a fresh in-memory store.
- `cd evolution/chassis_candidate_registry && mix run -e 'Chassis.Candidate.Registry.ensure_fixture_candidate(); Chassis.Candidate.Registry.list(tenant_ref: "tenant:dev") |> IO.inspect()'`:
  printed one `cand:dev:smoke` entry.
- `cd evolution/chassis_candidate_registry && mix chassis.evolution.candidate.show --candidate-ref cand:dev:smoke --json | jq '.candidate_ref'`:
  printed `"cand:dev:smoke"`.
- `cd evolution/chassis_candidate_registry && mix deps.tree`: only
  `chassis_evolution_contracts`, `chassis_evolution_receipts`, and
  `jason ~> 1.4`.
- `cd evolution/chassis_evolution_receipts && mix deps.tree`: only
  `chassis_evolution_contracts` and transitive `jason ~> 1.4`.
- `mix monorepo.compile --warnings-as-errors`: passed, selected 39 skipped 16
  total 55.
- `mix monorepo.test`: passed, selected 39 skipped 16 total 55.

## Failed / Deferred Checks

- `mix blitz.workspace.impact test --projects chassis_candidate_registry,chassis_evolution_receipts`
  failed before execution with Blitz option parsing:
  `** (Mix) Invalid options: [{"--projects", nil}]`.
- `mix ci` failed at workspace format checks on pre-existing out-of-phase files
  outside Phase 24 packages, including `core/chassis_core`,
  `core/chassis_inventory`, `core/chassis_mesh`, `core/chassis_receipts`,
  `core/chassis_stack`, `bootstrap/chassis_bootstrap`,
  `bootstrap/chassis_doctor`, `bootstrap/chassis_installer`,
  `adapters/chassis_artifact_fs`, and `adapters/chassis_systemd`.
- The checklist CLI entry names the manager binary form
  `./chassis evolution candidate.show`; Phase 24 used the package-local Mix
  task per post-Phase-20 CLI guidance.

## Generated Artifacts

- `_build/` and `deps/` were generated during package verification and are
  ignored/not committed.
- `.blitz/test_state_v1/indexes/task_states.ndjson` changed during CI and was
  restored before commits.
