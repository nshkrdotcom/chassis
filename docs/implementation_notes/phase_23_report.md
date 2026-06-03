# Phase 23 Report - Failure Batch Ingestion

Date: 2026-06-03

## Scope

- Permitted packages: `evolution/chassis_failure_batches` and
  `evolution/chassis_evolution_receipts` for `FailureBatchRecord`.
- Source commit: `881a9c4bf988f24c7a37e3605513e62092e20f01`.
- Sibling repo bridge work: none.

## Implemented

- Replaced shallow smoke markers with meaningful Phase 23 tests.
- Implemented `Chassis.FailureBatches.create_batch/2`, `fixture/0`,
  `list_batches/1`, `get_batch/2`, `link_evidence/3`, and JSON projection.
- Added source adapters for `Mezzanine`, `AppKit`, `AITrace`,
  `Observability`, and `StackLab` with stable `source_ref/0` values.
- Added deterministic failure-batch refs based on tenant, installation,
  source, evidence refs, bounded summary, and redaction posture.
- Added fail-closed tenant residency rejection before receipt writes.
- Added strict/default redaction behavior: raw bodies are only used for digest
  computation and are not stored in DTOs, receipt rows, span attributes, or
  projection summaries.
- Implemented `Chassis.Evolution.Receipts.FailureBatchRecord.new!/1` and an
  Agent-backed memory receipt store with put/get/list behavior.
- Converted future receipt records back to explicit
  `{:error, {:not_implemented, __MODULE__}}` placeholders for later phases.
- Added package-local Mix tasks:
  `mix chassis.evolution.batches` and
  `mix chassis.evolution.batch.show --batch-ref <ref>`.

## Test-First Evidence

- Initial `chassis_evolution_receipts` tests failed because
  `FailureBatchRecord.new!/1`, `Memory.start_link/1`, `Memory.get/2`, and
  future placeholder errors were missing.
- Initial `chassis_failure_batches` tests failed because the package could not
  expand `Chassis.Evolution.DTO.FailureBatch` and lacked contract dependency
  wiring.
- After dependency wiring, focused tests passed only after implementing
  residency rejection, digest stability, redaction checks, receipt storage, and
  package-local CLI JSON output.

## Verification

- `cd evolution/chassis_evolution_receipts && mix deps.get`: passed.
- `cd evolution/chassis_failure_batches && mix deps.get`: passed.
- `cd evolution/chassis_evolution_receipts && mix format --check-formatted`:
  passed.
- `cd evolution/chassis_failure_batches && mix format --check-formatted`:
  passed.
- `cd evolution/chassis_evolution_receipts && mix test`: 3 tests, 0 failures.
- `cd evolution/chassis_failure_batches && mix test`: 4 tests, 0 failures.
- `cd evolution/chassis_failure_batches && mix run -e '{:ok, b} = Chassis.FailureBatches.create_batch(Chassis.FailureBatches.fixture()); IO.inspect(b.failure_batch_ref)'`:
  printed `"failure_batch:9b5a4868ae7fcca8d6b5a267"`.
- `cd evolution/chassis_failure_batches && mix chassis.evolution.batches --json | jq '.items | length'`:
  printed `1`.
- `cd evolution/chassis_failure_batches && mix chassis.evolution.batch.show --batch-ref failure_batch:9b5a4868ae7fcca8d6b5a267 --json | jq '.failure_batch_ref'`:
  printed `"failure_batch:9b5a4868ae7fcca8d6b5a267"`.
- `cd evolution/chassis_failure_batches && mix deps.tree`: only
  `chassis_evolution_contracts`, `chassis_evolution_receipts`, and
  `jason ~> 1.4`.
- `cd evolution/chassis_evolution_receipts && mix deps.tree`: only
  `chassis_evolution_contracts` and transitive `jason ~> 1.4`.
- `mix monorepo.compile --warnings-as-errors`: passed, selected 38 skipped 17
  total 55.
- `mix monorepo.test`: passed, selected 38 skipped 17 total 55.

## Failed / Deferred Checks

- `mix blitz.workspace.impact test --projects chassis_failure_batches,chassis_evolution_receipts`
  failed before execution with Blitz option parsing:
  `** (Mix) Invalid options: [{"--projects", nil}]`.
- `mix ci` failed at workspace format checks on pre-existing out-of-phase files
  outside Phase 23 packages, including `core/chassis_inventory`,
  `core/chassis_core`, `core/chassis_mesh`, `core/chassis_receipts`,
  `core/chassis_stack`, `bootstrap/chassis_bootstrap`,
  `bootstrap/chassis_doctor`, `bootstrap/chassis_installer`,
  `adapters/chassis_artifact_fs`, and `adapters/chassis_systemd`.
- The checklist CLI entry names the manager binary form
  `./chassis evolution batches`; Phase 23 used package-local Mix tasks per the
  post-Phase-20 CLI guidance.

## Generated Artifacts

- `_build/` and `deps/` were generated during package verification and are
  ignored/not committed.
- `.blitz/test_state_v1/indexes/task_states.ndjson` changed during CI and was
  restored before commits.
