# Phase 18 Report - Extravaganza & StackCoder Full Wiring

## Scope

Phase 18 package-map scope is sibling integration across existing core/manager
surfaces with no new Chassis leaf package.

Sibling repos changed:

* `/home/home/p/g/n/extravaganza`
* `/home/home/p/g/n/stack_coder`

Chassis source files were not changed in this phase. Chassis received this
phase report only.

## Test-First Evidence

Focused Phase 18 tests were added before implementation:

* `extravaganza/apps/extravaganza_core/test/extravaganza_chassis_integration_test.exs`
* `stack_coder/apps/stack_coder/test/stack_coder/chassis_integration_test.exs`

Initial focused runs failed before implementation because
`AppKit.SpatialGateway.Request.GetActiveProfile` was unavailable in both sibling
repos. This proved the missing Phase 17 bridge dependency and prevented the
current shallow registration/topology code from satisfying the tests.

## Completed Behavior

Extravaganza:

* Added `app_kit_chassis_bridge` and `chassis_stack` path dependency wiring.
* Changed `Extravaganza.Application` to start `BootstrapWorker`,
  `ChassisRegistration`, and `VirtualServerSupervisor` under `:rest_for_one`.
* Replaced static registration with `AppKit.SpatialGateway` active-profile
  readback and deployment registration.
* Treated only explicit Chassis-unavailable registration failures
  (`:standalone`, `:registry_unavailable`) as standalone no-op startup.
* Added cached bootstrap installation-ref support in
  `Extravaganza.ProductBootstrap.cached_installation_ref/0`.
* Replaced static topology lists with `Chassis.Stack.ProfileResolver.resolve/2`
  node-pattern matching.
* Expanded all four `priv/chassis_profiles/*.json` manifests into service-spec
  manifests with virtual server placement.
* Moved new release/profile environment reads into application config so runtime
  product paths do not call `System.get_env`.

StackCoder:

* Added `app_kit_chassis_bridge` and `chassis_stack` path dependency wiring.
* Added real bootstrap failure handling, SpatialGateway registration, Chassis
  topology resolution, virtual-server child mapping, AgentIntake request
  construction, connector-pack supervision, deployment-manifest loading, and CLI
  positional support for `run`, `review-pr`, `context.index`, and
  `turn.history`.
* `StackCoder.AgentIntake.submit/2` now builds a typed
  `AppKit.Core.AgentIntake.AgentRunRequest`, stores prompt/repo as refs, and
  delegates to `AppKit.AgentIntake.start_agent_run/3`.
* Expanded all four `priv/profiles/*.json` manifests into service-spec manifests
  with virtual server placement.
* StackCoder default lower-plane children are sourced from opts or application
  config instead of hard-coded lower runtime modules, preserving the repo's
  product no-bypass constraints.

## Drift And Deferred Items

* `0521_stack_coder_full_spec.md` names ternary nodes `workflow@*` and
  `authority@*`; the implemented Chassis resolver currently uses
  `appkit@*`, `control@*`, and `data@*`. Phase 18 follows the implemented
  `Chassis.Stack.ProfileResolver` as the source of truth and records the doc
  drift.
* The checklist command `mix chassis.app.deploy extravaganza --profile
  profile:monolith --env dev` failed because no `chassis.app.deploy` Mix task
  exists. The available current form,
  `mix chassis.stack.deploy extravaganza --profile profile:monolith --env dev`,
  routed through the CLI and returned a structured `not_implemented` for
  `Chassis.CLI.Command.Stack.Deploy`. This is the existing Phase 20 CLI
  command-module gap, not a Phase 18 sibling wiring gap.
* The checklist-form smoke
  `MIX_ENV=test mix extravaganza.headless.smoke --deterministic` exited 0 but
  emitted an unavailable-surface envelope. The documented deterministic proof
  command with `--same-run --json` returned `ok: true`.

## QC Results

Extravaganza:

* `mix test test/extravaganza_chassis_integration_test.exs` - 5 tests, 0 failures.
* `mix test test/extravaganza_chassis_integration_test.exs test/extravaganza_dependency_sources_test.exs test/extravaganza_runtime_env_api_static_test.exs` - 9 tests, 0 failures.
* `rg -n "System\\.(get_env|fetch_env|fetch_env!|put_env|delete_env)" apps/extravaganza_core/lib apps/extravaganza_web/lib scripts/headless` - no matches.
* `mix ci` - passed, including no-bypass, format, compile, specs check, 169 core tests, 44 web tests, Credo, Dialyzer, and docs.
* `MIX_ENV=test mix extravaganza.headless.smoke --deterministic` - exit 0, emitted `ok: false` unavailable-surface envelope.
* `MIX_ENV=test mix extravaganza.headless.smoke --deterministic --same-run --json` - exit 0, emitted `ok: true`.

StackCoder:

* `mix test test/stack_coder/chassis_integration_test.exs` - 6 tests, 0 failures.
* `mix test test/stack_coder/local_e2e_test.exs` - 12 tests, 0 failures.
* `mix ci` - passed, including 20 tests and AppKit no-bypass scan.

Chassis:

* `mix monorepo.compile --warnings-as-errors` - passed,
  `selected=31 skipped=24 total=55`.
* `mix chassis.app.deploy extravaganza --profile profile:monolith --env dev` -
  failed, task not found; Mix suggested `chassis.stack.deploy`.
* `mix chassis.stack.deploy extravaganza --profile profile:monolith --env dev` -
  routed through CLI and returned `not_implemented` for
  `Chassis.CLI.Command.Stack.Deploy`, phase gate 11/package
  `:chassis_stack_manager`.

## Commits

Extravaganza:

* Path: `/home/home/p/g/n/extravaganza`
* Commit: `c9b1f06a124b816481ebfb15142671c0b2010056`
* Pushed: yes
* Files changed: application wiring, Chassis registration, product bootstrap,
  topology, virtual-server supervisor, dependency config, runtime config,
  four Chassis manifests, dependency-source test, Phase 18 tests.

StackCoder:

* Path: `/home/home/p/g/n/stack_coder`
* Commit: `0db1d041a0b528301757a37dc34afce39d5ed565`
* Pushed: yes
* Files changed: application wiring, Chassis integration modules, CLI,
  dependency config, four profile manifests, Phase 18 tests.

Chassis:

* Path: `/home/home/p/g/n/chassis`
* Source commit before report: `e4375294db8d0e92b6a41018718f1fee6b9588be`
* Report commit: pending at report creation time.
