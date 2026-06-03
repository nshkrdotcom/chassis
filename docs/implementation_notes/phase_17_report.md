# Phase 17 Report - AppKit Spatial Gateway

## 1. Scope

* Permitted Chassis package: `governance/chassis_appkit_surface`.
* Permitted sibling repo bridge work:
  * `/home/home/p/g/n/app_kit/bridges/chassis_bridge`
  * AppKit root dependency/facade needed for the required root
    `AppKit.SpatialGateway.get_active_profile/0` command.
  * `/home/home/p/g/n/app_kit/README.md`.

## 2. Test-First Evidence

* Chassis surface tests were written before implementation and first failed
  because `Chassis.AppKit.Surface.Error` did not exist.
* AppKit bridge tests were written before implementation and first failed
  because `AppKit.SpatialGateway.Request.GetActiveProfile` did not exist.

## 3. Completed Behavior

- [x] `chassis_appkit_surface` now provides the AppKit spatial schema surface:
  `Chassis.AppKit.Surface`, `Surface.Projection`, and `Surface.Error`.
- [x] Projection construction validates required `active_profile`, health/status
  enums, app atom shape, and label maps.
- [x] AppKit sibling bridge now ships the requested SpatialGateway layout:
  public API, request structs, backend behaviour, Local/Boundary/Standalone
  backends, Server, and Application supervisor modules.
- [x] `AppKit.SpatialGateway` resolves backends through
  `AppKit.BackendConfig.resolve/4`.
- [x] Local backend writes real `Chassis.AppRegistry.Entry` records and reads
  active profile state from the registry.
- [x] Boundary backend builds a Ring 0
  `boundary:appkit.chassis.read_deployment_projection:v1` envelope and uses a
  Chassis.Boundary-compatible dispatcher.
- [x] Standalone backend uses only `CHASSIS_DEPLOYMENT_PROFILE` for the fallback
  active profile.
- [x] `AppKit.SpatialGateway.Server` caches active profile readback through the
  public gateway API.
- [x] AppKit root command resolves the bridge package and returns
  `{:ok, "profile:monolith"}`.
- [x] AppKit README documents the bridge package, BackendConfig posture, and
  Chassis integration surface.
- [x] Future `AppKit.EvolutionSurface` paths fail closed with
  `{:error, {:not_implemented, AppKit.EvolutionSurface}}`.

## 4. Partial Or Deferred Items

* Mutating Boundary backend operations return
  `{:error, :boundary_operation_not_supported}` because the current Chassis Ring
  0 registry only exposes AppKit readback for
  `boundary:appkit.chassis.read_deployment_projection:v1`. Local backend covers
  registration and rollback hook injection in this phase.
* `AppKit.BackendStack` does not currently whitelist `:spatial_gateway_backend`.
  Phase 17 validated explicit `spatial_gateway_backend:` injection through
  `BackendConfig.resolve/4` without changing AppKit core outside the bridge
  package.
* `mix ci` in AppKit failed in unrelated DB-backed packages after Phase 17
  checks passed, due Postgres connection exhaustion in existing Mezzanine-backed
  tests.

## 5. Execution Integrity Audit Output

```text
$ rg -n "Application\\.(put_env|get_env)\\(:app_kit[,)]|receipt:.*smoke|rollback:appkit:smoke|evo:dev:smoke|status: :queued|implemented\\?\\(\\)" bridges/chassis_bridge lib/app_kit/chassis_facades.ex README.md
no matches
```

## 6. Cross-Phase Invariants

* I1 PASS - Chassis source changes are limited to
  `governance/chassis_appkit_surface`.
* I2 PASS - AppKit sibling changes are limited to the Chassis bridge package,
  root facade/dependency required for command execution, and README.
* I3 PASS - no generator scripts or bulk checklist edits were used.
* I4 PASS - no AppKit CLI/root path returns static payloads; the root
  `AppKit.SpatialGateway` module is loaded from `app_kit_chassis_bridge`.
* I5 PASS - tests assert Local side effects, Boundary dispatcher contract,
  Standalone fallback, BackendConfig explicit injection, Server caching, and
  future placeholder failure.
* I6 PASS - no `Application.put_env(:app_kit, ...)` runtime mutation was added.
* I7 PASS - generated Blitz runtime index changes were restored and not
  committed.

## 7. QC Gate Output

```text
$ (cd governance/chassis_appkit_surface && mix test && mix format --check-formatted)
4 tests, 0 failures

$ mix monorepo.compile --warnings-as-errors
Blitz impact summary: selected=31 skipped=24 total=55
exit 0

$ mix blitz.workspace.impact test --projects governance/chassis_appkit_surface
FAILED: Blitz 0.3.0 CLI rejected --projects with Invalid options: [{"--projects", nil}]

$ mix run -e 'workspace = Blitz.MixWorkspace.load!(); Blitz.MixWorkspace.Impact.run!(workspace, :test, [], only_projects: ["governance/chassis_appkit_surface"], force: true)'
Blitz impact summary: selected=1 skipped=0 total=1
governance/chassis_appkit_surface: 4 tests, 0 failures
```

## 8. Sibling Repo Bridge Work

* Repo path: `/home/home/p/g/n/app_kit`
* Files changed:
  * `bridges/chassis_bridge/lib/app_kit/spatial_gateway.ex`
  * `bridges/chassis_bridge/lib/app_kit/spatial_gateway/application.ex`
  * `bridges/chassis_bridge/lib/app_kit/spatial_gateway/backend.ex`
  * `bridges/chassis_bridge/lib/app_kit/spatial_gateway/backend/*.ex`
  * `bridges/chassis_bridge/lib/app_kit/spatial_gateway/request/*.ex`
  * `bridges/chassis_bridge/lib/app_kit/spatial_gateway/server.ex`
  * `bridges/chassis_bridge/lib/app_kit/evolution_surface.ex`
  * `bridges/chassis_bridge/mix.exs`
  * `bridges/chassis_bridge/test/chassis_bridge_test.exs`
  * `lib/app_kit/chassis_facades.ex`
  * `mix.exs`
  * `README.md`
* Tests and commands run:

```text
$ (cd bridges/chassis_bridge && mix deps.get && mix test && mix format --check-formatted)
6 tests, 0 failures

$ mix format --check-formatted mix.exs lib/app_kit/chassis_facades.ex
ok

$ mix deps.get && mix compile --warnings-as-errors && mix run -e 'IO.inspect(AppKit.SpatialGateway.get_active_profile())'
{:ok, "profile:monolith"}

$ mix test test/app_kit/workspace_test.exs
8 tests, 0 failures

$ mix ci
FAILED in monorepo test stage after deps, format, no-bypass scan, root tests,
monorepo compile, and bridges/chassis_bridge tests passed. Failures were
Postgrex/AshPostgres connection exhaustion in pre-existing DB-backed packages:
bridges/mezzanine_bridge, core/installation_surface, core/review_surface, and
core/work_surface.
```

* Commit: `f1a3815`, pushed to `origin/main`.

## 9. Commits And Push Status

* `/home/home/p/g/n/chassis`: source commit `9933dcc`, pushed to `origin/main`.
* `/home/home/p/g/n/app_kit`: sibling commit `f1a3815`, pushed to `origin/main`.
* Report commit follows this report file.
