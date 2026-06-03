# Phase 41 Report - Model Asset Conformance

Date: 2026-06-03

## Scope

- Package map scope: `proof/chassis_model_asset_conformance`.
- Sibling bridge scope:
  `/home/home/p/g/n/stack_lab/bridges/stacklab_chassis_bridge`.
- Additional CLI integration touched:
  - `lib/chassis/cli/model_commands.ex`
  - `lib/chassis/mix_tasks.ex`
  - `manager/chassis_cli/lib/chassis/cli/commands.ex`
  - `manager/chassis_cli/mix.exs`
  - `manager/chassis_cli/test/static_response_path_regression_test.exs`
- Reason for CLI integration: the Phase 41 smoke command requires
  `mix chassis.model.fixture --scenario ... --json`, and direct CLI dispatch
  for `model.fixture` had to execute the proof package instead of remaining a
  future-phase route.
- Chassis source commit:
  `fe6db16001fe6ddca5088740dec2ba99088c9ad2`, pushed.
- StackLab bridge commit:
  `22ae9bb876726f6808ff4acbdf97e19b2807282f`, pushed.

## Implemented

- Replaced the generated/static model asset conformance response with a real
  scenario runner.
- Added `Chassis.ModelAsset.Conformance.Scenario` behaviour and scenario modules
  for all Phase 41 model, hardware, and tensor matrix cases.
- Added scenario evidence execution through real package logic:
  - `Chassis.Model.WeightMaterializer`
  - `Chassis.HardwareGuard`
  - `Chassis.Tensor.Reload`
- Added StackLab catalog entries named `chassis.model.*.v1`.
- Added `Mix.Tasks.Chassis.Model.Fixture` in the proof package.
- Added root and manager CLI `model.fixture` command modules that dispatch to
  `Chassis.ModelAsset.Conformance`.
- Removed the root wrapper task for `chassis.model.fixture` to avoid duplicate
  Mix task ownership once the proof package is active.
- Rebuilt the tracked `./chassis` escript so the Phase 41 command is available
  through the binary.

## Test-First Evidence

- Initial proof package tests failed against the old static package because
  `Runner`, `Mix.Tasks.Chassis.Model.Fixture`, `Jason`, and required evidence
  keys were missing.
- Initial StackLab bridge and root task tests failed because
  `StackLab.ChassisBridge.run(:chassis_model_asset)` returned
  `{:error, {:not_implemented, :chassis_model_asset_conformance}}`.
- Final tests assert:
  - all 12 scenarios are declared in matrix order;
  - HF materialization verifies the digest and keeps model bytes out of the BEAM
    control channel;
  - hash mismatch refuses before runtime side effects;
  - hardware guard scenarios produce real admit/reject reasons;
  - tensor reload scenarios cover hot reload, restart fallback, missing rollback
    denial, rollback digest restoration, and digest mismatch refusal;
  - StackLab bridge evidence is non-empty and tagged as
    `chassis_model_asset`;
  - manager CLI dispatch executes conformance logic instead of a static payload.

## Verification

- `cd proof/chassis_model_asset_conformance && mix deps.get`: passed.
- `cd /home/home/p/g/n/chassis && mix format ...`: passed for touched Chassis
  Phase 41 files.
- `cd proof/chassis_model_asset_conformance && mix test`: 6 tests, 0 failures.
- `cd manager/chassis_cli && mix deps.get`: passed.
- `cd manager/chassis_cli && mix test test/static_response_path_regression_test.exs`:
  19 tests, 0 failures.
- `cd /home/home/p/g/n/chassis && MIX_ENV=test mix compile`: passed.
- `cd /home/home/p/g/n/chassis && MIX_ENV=test mix chassis.model.fixture --scenario hf_weight_materialization --json | jq '.digest_verified'`:
  returned `true`.
- First attempt of the same root smoke before `MIX_ENV=test mix compile` failed
  because dependency compile messages reached stdout before JSON and `jq`
  closed the pipe; after compiling test deps, the required smoke passed.
- `cd /home/home/p/g/n/stack_lab/bridges/stacklab_chassis_bridge && mix deps.get`:
  passed with a Hex cache ETS warning.
- `cd /home/home/p/g/n/stack_lab && mix format ...`: passed for touched
  StackLab Phase 41 files.
- `cd /home/home/p/g/n/stack_lab/bridges/stacklab_chassis_bridge && mix test`:
  4 tests, 0 failures.
- `cd /home/home/p/g/n/stack_lab && mix test test/stack_lab/run_task_test.exs`:
  3 tests, 0 failures.
- `cd /home/home/p/g/n/stack_lab && mix stack_lab.run --tag chassis_model_asset | grep PASS`:
  returned PASS lines for all 12 model asset proofs.
- `cd /home/home/p/g/n/chassis && mix monorepo.compile --warnings-as-errors`:
  passed, selected 55 skipped 0 total 55.
- `cd /home/home/p/g/n/chassis && mix escript.build`: passed and regenerated
  `./chassis`.
- `cd /home/home/p/g/n/chassis && ./chassis model.fixture --scenario hf_weight_materialization --json`:
  returned a live conformance payload with `"digest_verified": true`,
  `"bytes_via_beam_control?": false`, and `"control_channel_bytes": 0`.
- Required Chassis impact command:
  `mix blitz.workspace.impact test --projects chassis_model_asset_conformance`
  failed before execution with Blitz option parsing:
  `** (Mix) Invalid options: [{"--projects", nil}]`.

## Sibling Repo Bridge Work

- Repo path: `/home/home/p/g/n/stack_lab`.
- Files changed:
  - `bridges/stacklab_chassis_bridge/mix.exs`
  - `bridges/stacklab_chassis_bridge/lib/stack_lab/chassis_bridge.ex`
  - `bridges/stacklab_chassis_bridge/test/chassis_bridge_test.exs`
  - `test/stack_lab/run_task_test.exs`
- Tests run in repo:
  - `cd bridges/stacklab_chassis_bridge && mix deps.get`
  - `cd bridges/stacklab_chassis_bridge && mix test`
  - `mix test test/stack_lab/run_task_test.exs`
  - `mix stack_lab.run --tag chassis_model_asset | grep PASS`
- Commit hash: `22ae9bb876726f6808ff4acbdf97e19b2807282f`.

## Failed / Deferred Checks

- Required Blitz impact `--projects` command still fails at option parsing before
  tests execute. Focused tests, required smokes, StackLab bridge tests, and
  monorepo compile were used for verification.

## Generated Artifacts

- `_build/`, `deps/`, and temporary build outputs were generated during
  verification and are ignored/not committed.
- The tracked `./chassis` escript was intentionally regenerated and committed
  because the Phase 41 functional smoke uses that executable.
- `.blitz/test_state_v1/indexes/task_states.ndjson` changed during Chassis
  verification and was left unstaged as generated workspace state.
