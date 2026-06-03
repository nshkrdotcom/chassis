# Phase 39 Report - Model Cache

Date: 2026-06-03

## Scope

- Package map scope: `model/chassis_model_cache`.
- Additional CLI integration touched:
  - `lib/chassis/cli/model_commands.ex`
  - `manager/chassis_cli/lib/chassis/cli/commands.ex`
  - `manager/chassis_cli/test/static_response_path_regression_test.exs`
- Reason for CLI integration: the Phase 39 smoke command requires
  `./chassis model.cache.list ...`; the CLI command had no loaded module and
  was still marked as a future-phase not-implemented command.
- Chassis source commit: `58a3950e682614c7d125af1fb5d0c02b50812c48`, pushed.
- Sibling repo bridge work: none for Phase 39.

## Implemented

- Replaced the static model cache package with an ETS-backed target-host cache
  index.
- Added explicit receipt structs:
  - `Chassis.Model.Cache.Receipts.MaterializationRecord`
  - `Chassis.Model.Cache.Receipts.VerifyRecord`
  - `Chassis.Model.Cache.Receipts.EvictionRecord`
  - `Chassis.Model.Cache.Receipts.CacheReceipt`
- Added default cache root `/var/cache/nshkr/models` and default permissions
  `%{mode: "0750", owner: "nshkr_chassis_host", group: "nshkr_chassis_host"}`.
- Added `put/3`, `list/2`, `get/3`, `evict/3`, `disk_pressure/2`, and `reset/0`.
- Added tenant-aware LRU eviction for high-watermark and tenant-quota pressure.
- Added hit/miss cache receipts and eviction metrics with
  `chassis_model_weight_materialization_bytes_total{outcome: :evicted}`.
- Added raw-secret rejection before storage for secret-shaped strings.
- Added root and manager CLI command modules for `model.cache.list`.
- Rebuilt the tracked `./chassis` escript so the Phase 39 functional smoke runs
  against the updated root CLI command.

## Test-First Evidence

- Initial cache tests failed because generated receipt structs lacked required
  fields and cache APIs such as `reset/0` did not exist.
- Initial CLI regression failed because `model.cache.list` had no active command
  module.
- Final tests assert default root permissions, materialization/verify receipts,
  LRU eviction at high watermark, tenant partition protection, cache hit/miss
  receipts, raw-secret rejection, CLI list dispatch, and non-static output.

## Verification

- `cd model/chassis_model_cache && mix format`: passed.
- `cd model/chassis_model_cache && mix compile --warnings-as-errors`: passed.
- `cd model/chassis_model_cache && mix test`: 6 tests, 0 failures.
- `cd manager/chassis_cli && mix compile --warnings-as-errors`: passed.
- `cd manager/chassis_cli && mix test test/static_response_path_regression_test.exs`: 17 tests, 0 failures.
- `cd /home/home/p/g/n/chassis && mix compile --warnings-as-errors`: passed.
- `cd /home/home/p/g/n/chassis && mix escript.build`: passed and regenerated `./chassis`.
- `cd /home/home/p/g/n/chassis && ./chassis model.cache.list --host host:gpu-fixture --json | jq '.entries | length'`: returned `0`.
- `cd /home/home/p/g/n/chassis && ./chassis model.cache.list --host host:gpu-fixture --json | jq '.mode'`: returned `"0750"`.
- `cd /home/home/p/g/n/chassis && mix monorepo.compile --warnings-as-errors`: passed, selected 55 skipped 0 total 55.
- Required Chassis impact command:
  `mix blitz.workspace.impact test --projects chassis_model_cache`
  failed before execution with Blitz option parsing:
  `** (Mix) Invalid options: [{"--projects", nil}]`.

## Failed / Deferred Checks

- Required Blitz impact `--projects` command still fails at option parsing
  before tests execute. Focused tests and monorepo compile were used for
  verification.

## Generated Artifacts

- `_build/`, `deps/`, and temporary build outputs were generated during
  verification and are ignored/not committed.
- The tracked `./chassis` escript was intentionally regenerated and committed
  because the Phase 39 functional smoke uses that executable.
- `.blitz/test_state_v1/indexes/task_states.ndjson` changed during Chassis
  verification and was left unstaged as generated workspace state.
