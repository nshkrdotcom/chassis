# Phase 37 Report - Hardware Guard

Date: 2026-06-03

## Scope

- Package map scope: `model/chassis_hardware_guard`.
- Additional CLI integration touched:
  - `lib/chassis/cli.ex`
  - `lib/chassis/cli/hardware_commands.ex`
  - `manager/chassis_cli/lib/chassis/cli.ex`
  - `manager/chassis_cli/lib/chassis/cli/commands.ex`
  - `manager/chassis_cli/test/static_response_path_regression_test.exs`
- Reason for CLI integration: the Phase 37 smoke command requires
  `./chassis hardware.validate ...`; the CLI command had no loaded module and
  was still marked as a future-phase not-implemented command.
- Chassis source commit: `5bd47caa475d8a8e09322c37568bfc2383c300bc`, pushed.
- Sibling repo bridge work: none for Phase 37.

## Implemented

- Replaced the shallow host-ref string check with a structured hardware guard.
- Added `Chassis.HardwareGuard.CapabilitySnapshot` with canonical digesting.
- Added `Chassis.HardwareGuard.RequiredCapabilities` runtime specs for:
  - `runtime:crucible_bumblebee:cuda-small`
  - `runtime:crucible_bumblebee:cuda-large`
  - `runtime:llama_cpp_sdk:cpu-only`
  - `runtime:llama_cpp_sdk:metal`
  - `runtime:self_hosted_inference_core:rocm`
- Added digest-bound receipt structs:
  - `Chassis.HardwareGuard.Receipts.SnapshotRecord`
  - `Chassis.HardwareGuard.Receipts.AdmissionRecord`
- Added local, SSH, and container probe facades over bounded fixture snapshots
  that expose `/proc`, `/sys`, `lspci`, `nvidia-smi`, `rocm-smi`, and
  `system_profiler` probe posture in `raw_probe_summary`.
- Added closed-set admission checks for CPU architecture, cores, memory, root
  disk, model-cache disk, GPU vendor/free count, VRAM, compute capability,
  CUDA/ROCm ranges, Metal/Vulkan/OpenCL, container GPU runtime, and kernel
  modules.
- Added `hardware.validate` command modules for both root escript and
  `manager/chassis_cli`, dispatching to `Chassis.HardwareGuard.validate/3`.
- Rebuilt the tracked `./chassis` escript so the Phase 37 functional smoke runs
  against the updated root CLI command.

## Test-First Evidence

- Initial package tests failed against the shallow implementation because
  receipt structs lacked required keys, structured snapshots were missing, and
  scenario-level behavior did not exist.
- Initial CLI regression failed because `hardware.validate` exited with code 1.
- Final tests assert all six scenarios from `0535` §8, adapter snapshot capture,
  unknown host/runtime fail-closed behavior, digest-bound receipts, spans,
  rejection metrics, and reject-before-placement/runtime-start posture.

## Verification

- `cd model/chassis_hardware_guard && mix format`: passed.
- `cd model/chassis_hardware_guard && mix compile --warnings-as-errors`: passed.
- `cd model/chassis_hardware_guard && mix test`: 8 tests, 0 failures.
- `cd manager/chassis_cli && mix compile --warnings-as-errors`: passed.
- `cd manager/chassis_cli && mix test test/static_response_path_regression_test.exs`: 15 tests, 0 failures.
- `cd /home/home/p/g/n/chassis && mix compile --warnings-as-errors`: passed.
- `cd /home/home/p/g/n/chassis && mix escript.build`: passed and regenerated `./chassis`.
- `cd /home/home/p/g/n/chassis && ./chassis hardware.validate --host host:cpu-fixture --runtime runtime:crucible_bumblebee:cuda-small --json | jq '.admission_outcome'`: returned `"reject"`.
- `cd /home/home/p/g/n/chassis && mix monorepo.compile --warnings-as-errors`: passed, selected 55 skipped 0 total 55.
- Required Chassis impact command:
  `mix blitz.workspace.impact test --projects chassis_hardware_guard,chassis_cli`
  failed before execution with Blitz option parsing:
  `** (Mix) Invalid options: [{"--projects", nil}]`.

## Failed / Deferred Checks

- Required Blitz impact `--projects` command still fails at option parsing
  before tests execute. Focused tests and monorepo compile were used for
  verification.
- Direct modifications to `core/chassis_tenant` and `core/chassis_inventory`
  were deferred because the Phase 37 package map permits
  `model/chassis_hardware_guard`. The guard now exposes the callable API and
  CLI path required for those earlier-package integration points.

## Generated Artifacts

- `_build/`, `deps/`, and temporary build outputs were generated during
  verification and are ignored/not committed.
- The tracked `./chassis` escript was intentionally regenerated and committed
  because the Phase 37 functional smoke uses that executable.
- `.blitz/test_state_v1/indexes/task_states.ndjson` changed during Chassis
  verification and was left unstaged as generated workspace state.
