# Phase 40 Report - Tensor Reload

Date: 2026-06-03

## Scope

- Package map scope: `model/chassis_tensor_reload`.
- Additional CLI integration touched:
  - `lib/chassis/cli.ex`
  - `lib/chassis/cli/tensor_commands.ex`
  - `manager/chassis_cli/lib/chassis/cli.ex`
  - `manager/chassis_cli/lib/chassis/cli/commands.ex`
  - `manager/chassis_cli/test/static_response_path_regression_test.exs`
- Reason for CLI integration: the Phase 40 smoke command requires
  `./chassis tensor.reload ...`; tensor CLI commands were still future-phase
  not-implemented routes.
- Chassis source commit: `3487c9d597d45f0bb5ae75955cc982bbf3442d07`, pushed.
- Sibling repo bridge work: none for Phase 40.

## Implemented

- Replaced generated tensor adapter loops and permissive manifest validation with
  explicit reload lifecycle logic.
- Added `Chassis.Tensor.Reload.ManifestError`.
- Added `Chassis.Tensor.Reload.Adapter` behaviour and adapters:
  - `Bumblebee`
  - `LlamaCpp`
  - `SelfHostedInferenceCore`
- Added `Chassis.Tensor.Reload.PatchManifest` with `validate!/1`, fixture
  manifests, rollback requirements, no-op digest rejection, unsupported strategy
  rejection, and adapter resolution.
- Added receipt structs:
  - `Chassis.Tensor.Reload.Receipts.TensorReloadRecord`
  - `Chassis.Tensor.Reload.Receipts.TensorRollbackRecord`
- Added reload lifecycle with patch verification, hot reload, restart fallback
  when adapter returns `:unsupported`, health checks, spans, and metrics.
- Added rollback lifecycle that restores `restored_patch_digest` and emits a
  rollback receipt/span.
- Added root and manager CLI command modules for `tensor.reload` and
  `tensor.rollback`.
- Rebuilt the tracked `./chassis` escript so Phase 40 smokes run against the
  updated root CLI command.

## Test-First Evidence

- Initial tensor tests failed because generated receipt structs lacked fields
  and `ManifestError` did not exist.
- Initial CLI regression failed because `tensor.reload` returned exit code 1.
- Final tests assert hot reload, restart fallback, missing rollback denial before
  runtime side effects, rollback digest restoration, digest mismatch refusal,
  and CLI dispatch for reload/rollback.

## Verification

- `cd model/chassis_tensor_reload && mix format`: passed.
- `cd model/chassis_tensor_reload && mix compile --warnings-as-errors`: passed.
- `cd model/chassis_tensor_reload && mix test`: 5 tests, 0 failures.
- `cd manager/chassis_cli && mix compile --warnings-as-errors`: passed.
- `cd manager/chassis_cli && mix test test/static_response_path_regression_test.exs`: 18 tests, 0 failures.
- `cd /home/home/p/g/n/chassis && mix compile --warnings-as-errors`: passed.
- `cd /home/home/p/g/n/chassis && mix escript.build`: passed and regenerated `./chassis`.
- `cd /home/home/p/g/n/chassis && ./chassis tensor.reload --runtime runtime:crucible_bumblebee:cuda-small --patch patch:fixture:lora_001 --json | jq '.strategy_applied'`: returned `"hot_reload"`.
- `cd /home/home/p/g/n/chassis && ./chassis tensor.rollback --runtime runtime:crucible_bumblebee:cuda-small --patch patch:fixture:lora_001 --json | jq '.restored_patch_digest'`: returned `"sha256:rollback:lora_001"`.
- `cd /home/home/p/g/n/chassis && mix monorepo.compile --warnings-as-errors`: passed, selected 55 skipped 0 total 55.
- Required Chassis impact command:
  `mix blitz.workspace.impact test --projects chassis_tensor_reload`
  failed before execution with Blitz option parsing:
  `** (Mix) Invalid options: [{"--projects", nil}]`.

## Failed / Deferred Checks

- Required Blitz impact `--projects` command still fails at option parsing before
  tests execute. Focused tests and monorepo compile were used for verification.

## Generated Artifacts

- `_build/`, `deps/`, and temporary build outputs were generated during
  verification and are ignored/not committed.
- The tracked `./chassis` escript was intentionally regenerated and committed
  because the Phase 40 functional smoke uses that executable.
- `.blitz/test_state_v1/indexes/task_states.ndjson` changed during Chassis
  verification and was left unstaged as generated workspace state.
