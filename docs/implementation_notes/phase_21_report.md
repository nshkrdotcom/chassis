# Phase 21 Report - StackLab Proof Suite

Date: 2026-06-03

## Scope

- Permitted Chassis packages: `proof/chassis_conformance`,
  `proof/chassis_fixtures`, `proof/chassis_stacklab_bridge`.
- Chassis source commit:
  `723435d18418235f5481c42dc1050daa3ea8f581`.
- Sibling repo bridge work: `/home/home/p/g/n/stack_lab`.

## Implemented

- Replaced the static Chassis conformance proof list with an executable catalog
  of all 12 Phase 21 proofs.
- Added real fixture generation for four profiles, two apps, and dev/prod
  environments, plus a residency-violation fixture.
- Added local runtime helpers for AppRegistry, receipts, fences, checkpoints,
  deployment transaction attrs, topology composition, and mesh node derivation.
- Added `Chassis.StackLab.Bridge.RunConformance.run/1` and boundary `call/2`
  dispatch through `Chassis.Boundary.LocalAdapter`.
- Added package-local `mix chassis.proof.run --tag chassis --json`.
- Converted boundary response proof rows into string-safe DTO payloads while
  preserving detailed internal reports for JSON output.
- Added StackLab bridge integration and root `mix stack_lab.run --tag chassis
  --json` routing through the real Chassis proof runner.
- Kept future StackLab tags fail-closed with explicit not-implemented errors
  instead of success counts.

## Proof Catalog

All 12 proof names are implemented and passed locally:

- `chassis.boundary.local_adapter_equivalence.v1`
- `chassis.boundary.no_pid_payloads.v1`
- `chassis.boundary.no_raw_secret_payloads.v1`
- `chassis.boundary.codec_digest_stability.v1`
- `chassis.boundary.idempotency_required_for_mutations.v1`
- `chassis.boundary.citadel_fail_closed.v1`
- `chassis.deployment.profile_monolith_local`
- `chassis.deployment.profile_ternary_split_3_local`
- `chassis.deployment.profile_maximal_decoupled_local`
- `chassis.secrets.no_plaintext_in_receipts`
- `chassis.tenant.residency_enforcement`
- `chassis.metabolic.auto_rollback_on_pressure`

## Test-First Evidence

- `proof/chassis_fixtures` tests first failed on missing
  `deployment_fixtures/0` and `residency_violation_fixture/0`.
- `proof/chassis_conformance` tests first failed on missing executable
  `catalog/0` and `run/1`.
- `proof/chassis_stacklab_bridge` tests first failed on missing dependencies and
  then on boundary dispatch of unsafe proof payload atoms.
- StackLab bridge tests first failed because the existing bridge returned static
  counts without proof rows and returned success for unknown tags.
- StackLab root task test first failed because `mix stack_lab.run --tag chassis
  --json` emitted the old text-only `12/12 PASS` output.

## Verification

- `cd proof/chassis_fixtures && mix format --check-formatted`: passed.
- `cd proof/chassis_conformance && mix format --check-formatted`: passed.
- `cd proof/chassis_stacklab_bridge && mix format --check-formatted`: passed.
- `cd proof/chassis_fixtures && mix test`: 2 tests, 0 failures.
- `cd proof/chassis_conformance && mix test`: 3 tests, 0 failures.
- `cd proof/chassis_stacklab_bridge && mix test`: 3 tests, 0 failures.
- `mix monorepo.compile --warnings-as-errors`: passed, selected 35 skipped 20
  total 55.
- `mix monorepo.test`: passed, selected 35 skipped 20 total 55.
- `cd /home/home/p/g/n/stack_lab/bridges/stacklab_chassis_bridge && mix format --check-formatted`:
  passed.
- `cd /home/home/p/g/n/stack_lab && mix format --check-formatted`: passed.
- `cd /home/home/p/g/n/stack_lab/bridges/stacklab_chassis_bridge && mix test`:
  2 tests, 0 failures.
- `cd /home/home/p/g/n/stack_lab && mix test test/stack_lab/run_task_test.exs`:
  1 test, 0 failures.
- `cd /home/home/p/g/n/stack_lab && mix test`: 171 tests, 0 failures.
- `cd /home/home/p/g/n/stack_lab && mix stack_lab.run --tag chassis --json > /tmp/chassis_proof.json`:
  exit 0 after dependency graph was already compiled.
- `jq -e '.passed == 12 and .failed == 0 and .skipped == 0 and (.proofs | length == 12)' /tmp/chassis_proof.json`:
  exit 0.
- `jq -e '[.proofs[].name] == [...]' /tmp/chassis_proof.json`: exit 0 for
  the exact Phase 21 proof-name order.

## Failed / Deferred Checks

- `mix blitz.workspace.impact test --projects proof/chassis_fixtures,proof/chassis_conformance,proof/chassis_stacklab_bridge`
  failed before execution with Blitz option parsing:
  `** (Mix) Invalid options: [{"--projects", nil}]`.
- Chassis `mix ci` failed at workspace format checks on pre-existing
  out-of-phase files outside the Phase 21 packages, including
  `bootstrap/chassis_bootstrap`, `bootstrap/chassis_doctor`,
  `bootstrap/chassis_installer`, `core/chassis_inventory`,
  `core/chassis_mesh`, `core/chassis_receipts`, `core/chassis_stack`,
  `adapters/chassis_artifact_fs`, and `adapters/chassis_systemd`.
- StackLab `mix ci` failed in unrelated
  `examples/pressure_failover_drill` with
  `timed out waiting for pressure-failover transport result`. The
  `bridges/stacklab_chassis_bridge` package passed inside the same CI run.
- The first redirected StackLab proof command produced compile output before
  JSON because the graph was stale after edits. Rerunning the exact command
  after compilation produced parseable JSON and passed the required `jq` checks.

## Sibling Repo Bridge Work

- Repo path: `/home/home/p/g/n/stack_lab`.
- Commit: `e37b76fb5009dffc24738f9a024fa0c7bd760264`.
- Files changed:
  - `bridges/stacklab_chassis_bridge/lib/stack_lab/chassis_bridge.ex`
  - `bridges/stacklab_chassis_bridge/mix.exs`
  - `bridges/stacklab_chassis_bridge/test/chassis_bridge_test.exs`
  - `lib/mix/tasks/stack_lab.run.ex`
  - `mix.exs`
  - `test/stack_lab/run_task_test.exs`
- Tests run in sibling repo:
  - `mix format --check-formatted`
  - `bridges/stacklab_chassis_bridge mix format --check-formatted`
  - `bridges/stacklab_chassis_bridge mix test`
  - `mix test test/stack_lab/run_task_test.exs`
  - `mix test`
  - `mix stack_lab.run --tag chassis --json > /tmp/chassis_proof.json`
  - `jq` count and exact proof-name assertions
  - `mix ci` (failed only in unrelated pressure failover example)

## Generated Artifacts

- `/tmp/chassis_proof.json` and temporary receipt JSONL files under `/tmp` were
  generated during verification and are not committed.
- `.blitz/test_state_v1/indexes/task_states.ndjson` changed during CI in both
  repos and was restored before commits.
