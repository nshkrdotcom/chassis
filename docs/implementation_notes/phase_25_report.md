# Phase 25 Report - Coding Agent Port Runner

Date: 2026-06-03

## Scope

- Permitted package: `evolution/chassis_coding_agent_runner`.
- Source commit: `227060b5b6e4e9448df521ef38ced52d90a1c85d`.
- Sibling repo bridge work: none.

## Implemented

- Replaced the static success runner path with real OS command execution.
- Added `Chassis.Evolution.CodingAgentRunner.RunnerProfile` with finite runner
  kinds, binary path, working directory, env overrides, budget caps, and
  SecretRef validation for token-like env vars.
- Implemented `Chassis.Evolution.CodingAgentRunner.PortRunner` as the
  `Chassis.Evolution.CodingAgentRunner` behaviour implementation.
- Added real artifact capture for prompt summaries, diffs, and redacted build
  logs, with deterministic `stage:*` refs.
- Captured `cost_ref` and `token_ref` from runner output summaries.
- Wrote `CodeAgentRun` DTOs and optional `CodingAgentRunRecord` receipts.
- Added wall-clock budget enforcement using a brutal task shutdown and
  canonical `{:budget_exceeded, %{signal: :sigkill}}` errors.
- Added runner adapters for Codex, Claude, Gemini, Amp, OpenCode, Aider, and
  Custom, all delegating through the port runner contract.

## Test-First Evidence

- Initial tests failed at compile time because the package lacked dependency
  wiring for `CodeAgentRun`, `CodingAgentRunRecord`, and `SecretRef`.
- The previous implementation returned static maps; new tests require a real
  fixture binary, filesystem artifacts, receipt writes, redaction, and budget
  kill behavior.
- The adapter test exercises every provider adapter through the same fixture
  binary rather than asserting module existence.

## Verification

- `cd evolution/chassis_coding_agent_runner && mix deps.get`: passed.
- `cd evolution/chassis_coding_agent_runner && mix format --check-formatted`:
  passed.
- `cd evolution/chassis_coding_agent_runner && mix test`: 4 tests, 0 failures.
- `cd evolution/chassis_coding_agent_runner && mix deps.tree`: dependencies are
  `chassis_evolution_contracts`, `chassis_evolution_receipts`, and
  `chassis_secret_refs`; no `extravaganza` or `stack_coder` dependency.
- `rg -n "extravaganza|stack_coder|RAW_PROVIDER_TOKEN_PHASE25" evolution/chassis_coding_agent_runner/lib evolution/chassis_coding_agent_runner/test evolution/chassis_coding_agent_runner/mix.exs`:
  only found the raw provider token in the redaction test.
- Exact checklist smoke command
  `mix run -e 'IO.inspect(Chassis.Evolution.CodingAgentRunner.PortRunner.spawn_run(fixture_request(), runner_kind: :custom))'`
  failed because `fixture_request/0` is unqualified in the Elixir expression.
- Module-qualified smoke command
  `mix run -e 'IO.inspect(Chassis.Evolution.CodingAgentRunner.PortRunner.spawn_run(Chassis.Evolution.CodingAgentRunner.PortRunner.fixture_request(), runner_kind: :custom))'`
  returned `{:ok, %Chassis.Evolution.DTO.CodeAgentRun{...}}`.
- `mix monorepo.compile --warnings-as-errors`: passed, selected 40 skipped 15
  total 55.
- `mix monorepo.test`: passed, selected 40 skipped 15 total 55.

## Failed / Deferred Checks

- `mix blitz.workspace.impact test --projects chassis_coding_agent_runner`
  failed before execution with Blitz option parsing:
  `** (Mix) Invalid options: [{"--projects", nil}]`.
- The exact checklist smoke command is deferred because `fixture_request/0` is
  unqualified; the module-qualified form passes and executes real runner logic.
- `mix ci` failed at workspace format checks on pre-existing out-of-phase files
  outside Phase 25, including `core/chassis_inventory`, `core/chassis_mesh`,
  `core/chassis_receipts`, `core/chassis_stack`,
  `bootstrap/chassis_bootstrap`, `bootstrap/chassis_doctor`,
  `bootstrap/chassis_installer`, `adapters/chassis_artifact_fs`, and
  `adapters/chassis_systemd`.

## Generated Artifacts

- `_build/` and `deps/` were generated during package verification and are
  ignored/not committed.
- `.blitz/test_state_v1/indexes/task_states.ndjson` changed during CI and was
  restored before commits.
