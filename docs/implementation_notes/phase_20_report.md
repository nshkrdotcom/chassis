# Phase 20 Report - CLI Binary + DevProd Deploy Flows

Date: 2026-06-03

## Scope

- Permitted package: `manager/chassis_cli`.
- Source commit: `2099cd16f2656332a22460715780814213f12d3b`.
- Sibling repo bridge work: none.

## Implemented

- Added active command modules for the explicit Phase 20 command list:
  `stack.deploy`, `stack.status`, `stack.rollback`, `stack.diff`,
  `host.inventory`, `host.inspect`, `node.doctor`, `node.bootstrap`,
  `app.list`, `app.deploy`, `app.rollback`, `keys.add`, `keys.list`,
  `keys.show`, `keys.rotate`, `env.list`, `env.show`, and `proof.run`.
- Recorded checklist drift: the checklist labels this as "16 CLI commands" but
  lists 18. The implementation covers all 18 listed commands.
- Kept `proof.run` as the explicit Phase 21 future-package placeholder:
  it routes through `Chassis.CLI.Command.Proof.Run` and returns
  `{:error, {:not_implemented, __MODULE__, [phase: 21, package: :chassis_stacklab_bridge]}}`.
- Added real dispatch paths into package logic:
  - `stack.deploy` and `app.deploy` use Mezzanine by default.
  - `--no-mezzanine` calls `Chassis.StackManager.Transaction.run/1`.
  - inventory, diagnostics, bootstrap, environment, and key commands call their
    package modules instead of static CLI payloads.
- Added Bunt table rendering for `app.list` and `stack.status`.
- Added `--json` encoding coverage for command payloads.
- Added escript and Burrito release build configuration with Linux x86_64,
  Linux aarch64, macOS x86_64, and macOS arm64 targets.
- Added Burrito runtime dispatch so the wrapped Linux binary invokes the same
  CLI router instead of only starting a release supervisor.

## Test-First Evidence

- Initial focused test run before implementation failed to compile because the
  CLI had no package dependencies for `Chassis.Receipts.DeploymentRecord`. This
  was the expected failure proving tests were not only asserting module presence.
- New and updated tests assert command dispatch, side effects, unhappy paths,
  redaction, table formatting, and future-phase placeholder routing.

## Verification

- `mix format --check-formatted ...phase20 files...`: passed.
- `cd manager/chassis_cli && mix test`: 19 tests, 0 failures.
- `cd manager/chassis_cli && mix escript.build`: passed.
- `cd manager/chassis_cli && ./chassis --help`: exit 0; command table printed.
- `cd manager/chassis_cli && ./chassis stack.deploy --profile profile:monolith --env dev --json`: exit 0; returned `status: "active"` via Mezzanine.
- `cd manager/chassis_cli && ./chassis stack.deploy --profile profile:monolith --env dev --json | jq '.status' | grep -q '"active"'`: exit 0.
- `cd manager/chassis_cli && mix burrito.build --overwrite`: exit 0; produced all four configured targets.
- `cd manager/chassis_cli && timeout 120 ./burrito_out/chassis_linux_x86_64 --help`: exit 0; native wrapped binary reached the real command table. Dev Burrito emitted wrapper debug output before CLI output.
- `cd manager/chassis_cli && timeout 120 ./burrito_out/chassis_linux_x86_64 stack.deploy --profile profile:monolith --env dev --json | tail -n 1 | jq -e '.status == "active"'`: exit 0.
- `mix monorepo.compile --warnings-as-errors`: passed, selected 32 skipped 23 total 55.
- `mix monorepo.test`: passed, selected 32 skipped 23 total 55.
- `rg -n "Application\\.put_env" manager/chassis_cli`: no matches.

## Failed / Deferred Checks

- `mix blitz.workspace.impact test --projects manager/chassis_cli` failed before execution with Blitz option parsing:
  `** (Mix) Invalid options: [{"--projects", nil}]`.
- `mix ci` failed at workspace format checks on pre-existing out-of-phase files
  outside `manager/chassis_cli` (`core/chassis_core`, `core/chassis_inventory`,
  `core/chassis_mesh`, `core/chassis_receipts`, `core/chassis_stack`,
  `bootstrap/chassis_bootstrap`, `bootstrap/chassis_doctor`,
  `bootstrap/chassis_installer`, `adapters/chassis_artifact_fs`, and
  `adapters/chassis_systemd`). The Phase 20 files passed targeted format.
- The real VPS fixture command
  `./chassis app.deploy extravaganza --profile profile:ternary-split-3 --env prod`
  was not run against real VPS nodes because no real VPS fixture environment is
  available in the current workspace. The local Mezzanine and direct StackManager
  deploy paths were covered by unit tests and CLI smokes.

## Generated Artifacts

- `manager/chassis_cli/chassis`, `manager/chassis_cli/burrito_out/`,
  `manager/chassis_cli/_build/`, and `manager/chassis_cli/deps/` were generated
  during verification and are ignored/not committed.
