# Phase 38 Report - HF Hub and Weight Materializer

Date: 2026-06-03

## Scope

- Package map scope:
  - `adapters/chassis_hf_hub`
  - `model/chassis_weight_materializer`
- Additional CLI integration touched:
  - `lib/chassis/cli.ex`
  - `lib/chassis/cli/model_commands.ex`
  - `manager/chassis_cli/lib/chassis/cli.ex`
  - `manager/chassis_cli/lib/chassis/cli/commands.ex`
  - `manager/chassis_cli/test/static_response_path_regression_test.exs`
- Reason for CLI integration: the Phase 38 smoke command requires
  `./chassis model.materialize ...`; the CLI command had no loaded module and
  was still marked as a future-phase not-implemented command.
- Chassis source commit: `f05cfa6fc2b5bc1325a907b5f4301596670416a6`, pushed.
- Sibling repo bridge work: none for Phase 38.

## Implemented

- Replaced HF Hub and materializer smoke/static behavior with fixture-backed
  operational logic.
- Added `Chassis.HFHub` target-host adapter that:
  - resolves fixture manifests without raw tokens,
  - enforces writes under `/var/cache/nshkr/models`,
  - emits target-side `hf_hub_download` command posture,
  - supports resume from partial downloads,
  - honors `:bulk` and `:priority` bandwidth classes,
  - returns `control_channel_bytes: 0`.
- Added `Chassis.Model.Manifest` with fixture manifest resolution and digest
  helpers.
- Added `Chassis.Model.WeightSource` behaviour plus explicit source modules:
  - `Chassis.Model.WeightSource.HFHub`
  - `Chassis.Model.WeightSource.LocalCache`
  - `Chassis.Model.WeightSource.SharedCache`
  - `Chassis.Model.WeightSource.ArtifactMirror`
- Added receipt structs:
  - `Chassis.Model.Receipts.MaterializationRecord`
  - `Chassis.Model.Receipts.VerifyRecord`
- Added `Chassis.Model.WeightMaterializer.materialize/2` with request
  validation, source selection, digest verification, mismatch rejection,
  target-host cache path selection, and Phase 39 deferred cache write events.
- Added root and manager CLI command modules for `model.materialize`.
- Rebuilt the tracked `./chassis` escript so the Phase 38 functional smoke runs
  against the updated root CLI command.

## Test-First Evidence

- Initial HF Hub tests failed because `Chassis.HFHub` did not exist.
- Initial materializer tests failed because materialization receipt structs did
  not exist and the previous implementation returned static success.
- Initial CLI regression failed because `model.materialize` exited with code 1
  and `model.cache.list` still had Phase 40 metadata.
- Final tests assert digest verification, digest mismatch rejection, zero BEAM
  control-channel bytes, partial download resume, bandwidth class propagation,
  cache-root enforcement, source strategy coverage, unknown model/strategy
  fail-closed behavior, and Phase 39 cache-write deferral.

## Verification

- `cd adapters/chassis_hf_hub && mix format`: passed.
- `cd adapters/chassis_hf_hub && mix compile --warnings-as-errors`: passed.
- `cd adapters/chassis_hf_hub && mix test`: 4 tests, 0 failures.
- `cd model/chassis_weight_materializer && mix format`: passed.
- `cd model/chassis_weight_materializer && mix compile --warnings-as-errors`: passed.
- `cd model/chassis_weight_materializer && mix test`: 6 tests, 0 failures.
- `cd manager/chassis_cli && mix compile --warnings-as-errors`: passed.
- `cd manager/chassis_cli && mix test test/static_response_path_regression_test.exs`: 16 tests, 0 failures.
- `cd /home/home/p/g/n/chassis && mix compile --warnings-as-errors`: passed.
- `cd /home/home/p/g/n/chassis && mix escript.build`: passed and regenerated `./chassis`.
- `cd /home/home/p/g/n/chassis && ./chassis model.materialize --model model:hf:qwen3-small-fixture --target host:gpu-fixture --verify-sha256 --dry-run --json | jq '.digest_verified'`: returned `true`.
- `cd /home/home/p/g/n/chassis && ./chassis model.materialize --model model:hf:qwen3-small-fixture --target host:gpu-fixture --verify-sha256 --dry-run --json | jq '.[\"bytes_via_beam_control?\"]'`: returned `false`.
- `cd /home/home/p/g/n/chassis && mix monorepo.compile --warnings-as-errors`: passed, selected 55 skipped 0 total 55.
- Required Chassis impact command:
  `mix blitz.workspace.impact test --projects chassis_hf_hub,chassis_weight_materializer`
  failed before execution with Blitz option parsing:
  `** (Mix) Invalid options: [{"--projects", nil}]`.

## Failed / Deferred Checks

- Required Blitz impact `--projects` command still fails at option parsing
  before tests execute. Focused tests and monorepo compile were used for
  verification.
- Cache writes are emitted as `%{status: :deferred_phase_39, package:
  :chassis_model_cache, ...}` events only. `model/chassis_model_cache` was not
  modified per the Phase 38 package-boundary rule.

## Generated Artifacts

- `_build/`, `deps/`, and temporary build outputs were generated during
  verification and are ignored/not committed.
- The tracked `./chassis` escript was intentionally regenerated and committed
  because the Phase 38 functional smoke uses that executable.
- `.blitz/test_state_v1/indexes/task_states.ndjson` changed during Chassis
  verification and was left unstaged as generated workspace state.
