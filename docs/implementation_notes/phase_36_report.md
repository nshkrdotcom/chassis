# Phase 36 Report - Evolution Conformance StackLab Proof

Date: 2026-06-03

## Scope

- Package map scope: `proof/chassis_evolution_conformance`.
- Required sibling bridge scope: `/home/home/p/g/n/stack_lab/bridges/stacklab_chassis_bridge`.
- Additional CLI integration touched:
  - `lib/chassis/cli.ex`
  - `lib/chassis/cli/evolution_commands.ex`
  - `manager/chassis_cli/lib/chassis/cli.ex`
  - `manager/chassis_cli/lib/chassis/cli/commands.ex`
  - `manager/chassis_cli/test/static_response_path_regression_test.exs`
- Reason for CLI integration: the root Phase 36 smoke command initially routed
  through `chassis_cli` and returned a Phase 36 not-implemented payload. The
  checklist requires the CLI command and the execution contract forbids a static
  response path, so the CLI commands were wired to the proof package logic.
- Chassis source commit: `2d2651469d687c41c42907cf35a88ed29c4defac`, pushed.
- StackLab bridge commit: `cfaa54bc4ef7267b268731d6d491430406ce596e`, pushed.

## Implemented

- Replaced the static `chassis_evolution_conformance` module and smoke test with
  a deterministic conformance harness that executes all twelve scenarios from
  `0533_chassis_evolution_stacklab_proof.md`.
- Added explicit scenario modules for:
  - `source_level_patch_success`
  - `forced_probe_rollback`
  - `authority_denied`
  - `consent_missing`
  - `trial_regression_blocked`
  - `coding_agent_crash`
  - `candidate_build_failure`
  - `health_probe_timeout`
  - `state_volume_missing`
  - `forbidden_production_state_in_trial`
  - `appkit_raw_diff_blocked`
  - `receipt_redaction_check`
- Added receipt, projection, span, metric, Citadel decision, operator consent,
  trial, scoring, swap, host-call, candidate registry, and AppKit product-safe
  evidence for each scenario.
- Added global invariant proofs for raw-secret redaction, trial production-state
  isolation, digest stability, regression promotion blocking, Citadel/operator
  consent requirements, health-probe rollback, product-safe AppKit readbacks,
  AITrace spans, metrics, and Mezzanine projections.
- Added `Chassis.Evolution.Conformance.Asserts` for final state, span, metric,
  receipt, redaction, and trial-state assertions.
- Added harness-owned `Chassis.AITrace.Bridge.TestEmitter` plus integration with
  existing `Chassis.Metrics.Backend.Test` so Phase 36 can validate DTO capture
  without mutating earlier observability packages.
- Added Mix tasks:
  - `mix chassis.evolution.fixture --scenario <name> --json`
  - `mix chassis.evolution.proof --app ... --require-trial --require-citadel-consent --require-health-gated-swap --require-rollback-proof`
- Added root and manager CLI command modules for `evolution.fixture` and
  `evolution.proof`; both dispatch to `Chassis.Evolution.Conformance` and return
  the proof package's JSON-safe evidence.
- Removed duplicate root Mix-task shims for `chassis.evolution.fixture` and
  `chassis.evolution.proof` after the root workspace began depending on the
  proof package; the task names now come from the proof package to avoid module
  redefinition warnings under `--warnings-as-errors`.

## Test-First Evidence

- Initial conformance tests failed because scenario modules, Mix tasks, Jason
  dependency, AITrace test emitter, and metrics dependency were missing.
- Initial StackLab bridge tests failed because `:chassis_evolution` returned the
  explicit not-implemented placeholder.
- Initial root CLI regression tests failed because `evolution.fixture` and
  `evolution.proof` exited with code 1 and `evolution.proof` was absent from
  help output.
- Final tests assert non-static behavior: scenario lifecycle evidence,
  unhappy-path authority/consent/trial blocks, receipt redaction grep exit 1,
  DTO emitter/backend capture, all twelve scenarios, CLI JSON derived from
  conformance execution, and StackLab's 21 proof catalog entries.

## Sibling Repo Bridge Work

- Repo path: `/home/home/p/g/n/stack_lab`.
- Files changed:
  - `bridges/stacklab_chassis_bridge/lib/stack_lab/chassis_bridge.ex`
  - `bridges/stacklab_chassis_bridge/mix.exs`
  - `bridges/stacklab_chassis_bridge/mix.lock`
  - `bridges/stacklab_chassis_bridge/test/chassis_bridge_test.exs`
  - `test/stack_lab/run_task_test.exs`
- Tests run in sibling repo:
  - `cd bridges/stacklab_chassis_bridge && mix format`: passed.
  - `cd bridges/stacklab_chassis_bridge && mix compile --warnings-as-errors`: passed.
  - `cd bridges/stacklab_chassis_bridge && mix test`: 3 tests, 0 failures.
  - `cd /home/home/p/g/n/stack_lab && mix test test/stack_lab/run_task_test.exs`: 2 tests, 0 failures.
  - `cd /home/home/p/g/n/stack_lab && mix stack_lab.run --tag chassis_evolution | grep PASS`: passed, 21 PASS lines.
- Commit hash: `cfaa54bc4ef7267b268731d6d491430406ce596e`, pushed.

## Verification

- `cd proof/chassis_evolution_conformance && mix format`: passed.
- `cd proof/chassis_evolution_conformance && mix compile --warnings-as-errors`: passed.
- `cd proof/chassis_evolution_conformance && mix test`: 6 tests, 0 failures.
- `cd manager/chassis_cli && mix test test/static_response_path_regression_test.exs`: 14 tests, 0 failures.
- `cd /home/home/p/g/n/chassis && MIX_ENV=test mix chassis.evolution.fixture --scenario source_level_patch_success --json | jq '.final_state'`: returned `"committed"`.
- `cd /home/home/p/g/n/chassis && MIX_ENV=test mix chassis.evolution.proof --app extravaganza --profile profile:ternary-split-3 --env prod --fixture fixture:source_level_repair_001 --require-trial --require-citadel-consent --require-health-gated-swap --require-rollback-proof --json | jq '.passed'`: returned `12`.
- Receipt redaction grep audit for `receipt_redaction_check`: `grep -rEi 'BEGIN PRIVATE KEY|password|api_key'` returned exit code 1.
- `cd /home/home/p/g/n/chassis && mix monorepo.compile --warnings-as-errors`: passed after removing duplicate root Mix task shims.
- Required Chassis impact command:
  `mix blitz.workspace.impact test --projects chassis_evolution_conformance,chassis_cli`
  failed before execution with Blitz option parsing:
  `** (Mix) Invalid options: [{"--projects", nil}]`.

## Failed / Deferred Checks

- Required Blitz impact `--projects` command still fails at option parsing
  before tests execute. Focused package/CLI/StackLab tests and monorepo compile
  were used for verification.
- The Phase 36 package map did not list `manager/chassis_cli` or root CLI files,
  but the required smoke path already routed through those files and returned a
  Phase 36 not-implemented payload. The CLI integration was implemented as the
  maximum safe subset and is recorded as an explicit scope expansion.

## Generated Artifacts

- `_build/`, `deps/`, and temporary receipt files were generated during
  verification and are ignored/not committed.
- `.blitz/test_state_v1/indexes/task_states.ndjson` changed during Chassis
  verification and was left unstaged as generated workspace state.
