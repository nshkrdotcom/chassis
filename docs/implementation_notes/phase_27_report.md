# Phase 27 Report - Container Runtime Adapter

Date: 2026-06-03

## Scope

- Checklist packages: `adapters/chassis_container`, `adapters/chassis_systemd`,
  `adapters/chassis_ssh`, `host/chassis_trial_supervisor`.
- Package-map permitted package: `adapters/chassis_container`.
- Source commit: `afb57cb5bb47d671bef6278a5676093ea1f4dec5`.
- Sibling repo bridge work: none.

## Implemented

- Replaced the generated static container adapter with command-backed Docker and
  Podman adapters.
- Extended `Chassis.Container.Adapter` with `build/2`, `run/2`, `inspect/2`,
  and `stop/2`.
- Implemented `Chassis.Container.Adapter.Runtime` to execute container runtime
  commands through `System.cmd/3`, with injectable command paths for tests and
  default `docker`/`podman` executables for operational use.
- Added build command construction for `build --quiet --tag <image> <context>`
  with digest capture and `:docker_build` / `:podman_build` strategy metadata.
- Added isolated trial run command construction with container name, `--network
  none`, trial BEAM node/cookie env vars, port-range publishing, bind-mount
  args, container refs, and lifecycle timestamps.
- Added inspect and stop command paths with structured failure reporting.

## Test-First Evidence

- Initial tests failed because the package only exposed arity-1 static
  `build/1`, `run/1`, and `stop/1` functions and no inspect path.
- The new tests require an actual executable fixture runtime, command logs,
  digest capture from runtime output, Podman strategy selection, isolated
  container run arguments, stop/inspect commands, required-field failures before
  runtime invocation, and runtime exit-status propagation.

## Verification

- `cd adapters/chassis_container && mix format --check-formatted`: passed.
- `cd adapters/chassis_container && mix test`: 6 tests, 0 failures.
- `cd adapters/chassis_container && mix deps.tree`: no runtime dependencies.
- Direct fixture smoke:
  `cd adapters/chassis_container && RUNTIME=<fixture> CONTEXT=<context> mix run -e '...Docker.build...Docker.run...'`
  returned `container:docker:smoke-container`.
- `mix monorepo.compile --warnings-as-errors`: passed.
- `mix monorepo.test`: passed, selected 43 skipped 12 total 55.

## Failed / Deferred Checks

- `mix blitz.workspace.impact test --projects chassis_container` failed before
  execution with Blitz option parsing:
  `** (Mix) Invalid options: [{"--projects", nil}]`.
- Checklist systemd, SSH, and `host/chassis_trial_supervisor` materialization
  work is deferred because the package map restricts Phase 27 writes to
  `adapters/chassis_container`.
- Exact `./chassis node.trial ... --kind container` smoke is deferred because
  wiring `chassis_trial_runtime` and manager-binary CLI dispatch is outside the
  Phase 27 package-map scope. The package-local container adapter smoke passed.
- `mix ci` failed during workspace format checks on pre-existing out-of-phase
  files and dependency directories outside Phase 27.

## Generated Artifacts

- `_build/` and `deps/` were generated during package verification and are
  ignored/not committed.
- `.blitz/test_state_v1/indexes/task_states.ndjson` changed during CI and was
  restored before commits.
