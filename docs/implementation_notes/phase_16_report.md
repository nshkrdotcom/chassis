# Phase 16 Report - Mezzanine Deployment Workflow Bridge

## 1. Scope

* Permitted Chassis packages (per 0537):
  * `core/chassis_projection`
  * `governance/chassis_mezzanine_bridge`
* Permitted sibling repo bridge work:
  * `/home/home/p/g/n/mezzanine/bridges/mezzanine_chassis_bridge`
  * Mezzanine root Mix tasks needed for the required E2E command.

## 2. Test-First Evidence

* Chassis projection tests were written before implementation and first failed
  because `Chassis.Projection.Store.Memory` and
  `Chassis.Projection.ChassisDeploymentProjection` were missing.
* Chassis bridge tests were written before implementation and first failed
  because the generated bridge package had no `chassis_boundary` dependency and
  no concrete protocol modules.
* Mezzanine bridge tests were written before sibling implementation and first
  failed because `Chassis.Boundary.Error` was unavailable, proving the generated
  sibling package had no Chassis bridge dependency.

## 3. Completed Behavior

- [x] `Chassis.Projection.ChassisDeploymentProjection` reduces deployment
  receipt events into operator-safe deployment projections.
- [x] `Chassis.Projection.Store.Memory` supports idempotent projection upsert,
  latest query, and list.
- [x] `Chassis.Mezzanine.Bridge.MaterializeDeployment` dispatches through
  `Chassis.Boundary.dispatch/2`, runs `Chassis.StackManager.Transaction.run/1`,
  preserves envelope authority via the StackManager authorization hook, and
  publishes a deployment projection event.
- [x] `Chassis.Mezzanine.Bridge.RollbackDeployment`, `InspectHost`,
  `ValidateTopology`, `DrainHost`, and `ProvisionHost` execute concrete handler
  logic and return boundary-codec-safe payloads.
- [x] `Chassis.Mezzanine.Bridge.Outbox` enqueues idempotently and only marks
  events delivered after publisher success.
- [x] `ProjectionPublisher` converts deployment receipts into Chassis deployment
  projection outbox events.
- [x] `Mezzanine.Workflow.ChassisDeploymentWorkflow` and
  `Mezzanine.Workflow.ChassisRollbackWorkflow` ship in the sibling bridge
  package and call the Chassis bridge path.
- [x] `Mezzanine.Outbox.ChassisDrainWorker` drains Chassis deployment events into
  `Mezzanine.Read.ChassisDeploymentProjection`.
- [x] `Mezzanine.Read.ChassisDeploymentProjection` reduces outbox events into an
  in-memory read store and a temp-file store for separate CLI invocations.
- [x] Root Mezzanine CLI tasks now call workflow/projection modules instead of
  printing static smoke strings.
- [x] Future Chassis Evolution sibling placeholders fail closed with
  `{:error, {:not_implemented, __MODULE__}}`.

## 4. Partial Or Deferred Items

* The exact checklist QC command uses
  `mix mezzanine.workflow.dispatch chassis_materialize_deployment --topology topology:monolith --env dev`
  and `mix mezzanine.read.get chassis_deployment --last 1`. The implemented
  root task supports the documented workflow name without those legacy option
  spellings and the implemented projection command is
  `mix mezzanine.read.get chassis_deployment_projection`.
* The Chassis root CLI stack deploy path remains later-phase work; Phase 16 uses
  the Mezzanine sibling workflow command required by this phase.

## 5. Execution Integrity Audit Output

```text
$ rg -n "Chassis\\.Boundary\\.dispatch|Bridge\\.dispatch|receipt:.*smoke|status=dispatched|status=active receipt_ref=receipt:mezzanine|not_implemented" governance/chassis_mezzanine_bridge core/chassis_projection
governance/chassis_mezzanine_bridge/test/mezzanine_bridge_test.exs:16: Chassis.Boundary.dispatch(envelope, opts)
governance/chassis_mezzanine_bridge/test/mezzanine_bridge_test.exs:*: Bridge.dispatch(...)
governance/chassis_mezzanine_bridge/lib/chassis/mezzanine_bridge.ex:6: `Chassis.Boundary.dispatch/2` with the concrete protocol module attached.
no static smoke success path remains in touched Chassis bridge/projection source

$ rg -n "Chassis\\.Boundary\\.dispatch|Chassis\\.Mezzanine\\.Bridge\\.dispatch|receipt:.*smoke|status=dispatched|status=active receipt_ref=receipt:mezzanine|not_implemented" bridges/mezzanine_chassis_bridge lib/mix/tasks/mezzanine.workflow.dispatch.ex lib/mix/tasks/mezzanine.read.get.ex
bridges/mezzanine_chassis_bridge/test/chassis_workflows_test.exs:16: Chassis.Boundary.dispatch(envelope, opts)
bridges/mezzanine_chassis_bridge/lib/mezzanine/workflow/chassis_workflows.ex:143: Chassis.Mezzanine.Bridge.dispatch(...)
bridges/mezzanine_chassis_bridge/lib/mezzanine/workflow/chassis_workflows.ex:262: {:error, {:not_implemented, __MODULE__}}
bridges/mezzanine_chassis_bridge/lib/mezzanine/workflow/chassis_workflows.ex:463: {:error, {:not_implemented, __MODULE__}}
no static Mezzanine CLI smoke success path remains in touched source
```

## 6. Cross-Phase Invariants

* I1 PASS - Chassis source changes are limited to Phase 16 permitted packages.
* I2 PASS - Mezzanine sibling changes are limited to the permitted bridge
  package plus root tasks/dependency required for the E2E command.
* I3 PASS - no generator scripts or bulk checklist edits were used.
* I4 PASS - no CLI response path returns static payloads; root Mezzanine CLI
  calls workflow/projection modules.
* I5 PASS - tests assert side effects, unhappy paths, outbox delivery posture,
  boundary dispatch, projection persistence, and fail-closed future placeholders.
* I6 PASS - generated Blitz runtime index changes were restored and not
  committed.
* I7 PASS - no production/receipt/snapshot pointer was promoted.

## 7. QC Gate Output

```text
$ (cd core/chassis_projection && mix test && mix format --check-formatted)
4 tests, 0 failures

$ (cd governance/chassis_mezzanine_bridge && mix test && mix format --check-formatted)
6 tests, 0 failures

$ mix monorepo.compile --warnings-as-errors
Blitz impact summary: selected=30 skipped=25 total=55
exit 0

$ mix blitz.workspace.impact test --projects core/chassis_projection,governance/chassis_mezzanine_bridge
FAILED: Blitz 0.3.0 CLI rejected --projects with Invalid options: [{"--projects", nil}]

$ mix run -e 'workspace = Blitz.MixWorkspace.load!(); Blitz.MixWorkspace.Impact.run!(workspace, :test, [], only_projects: ["core/chassis_projection", "governance/chassis_mezzanine_bridge"], force: true)'
Blitz impact summary: selected=2 skipped=0 total=2
core/chassis_projection: 4 tests, 0 failures
governance/chassis_mezzanine_bridge: 6 tests, 0 failures
```

## 8. Sibling Repo Bridge Work

* Repo path: `/home/home/p/g/n/mezzanine`
* Files changed:
  * `bridges/mezzanine_chassis_bridge/lib/mezzanine/workflow/chassis_workflows.ex`
  * `bridges/mezzanine_chassis_bridge/mix.exs`
  * `bridges/mezzanine_chassis_bridge/test/chassis_workflows_test.exs`
  * `lib/mix/tasks/mezzanine.workflow.dispatch.ex`
  * `lib/mix/tasks/mezzanine.read.get.ex`
  * `mix.exs`
* Tests and commands run:

```text
$ (cd bridges/mezzanine_chassis_bridge && mix test && mix format --check-formatted)
5 tests, 0 failures

$ mix format --check-formatted mix.exs lib/mix/tasks/mezzanine.workflow.dispatch.ex lib/mix/tasks/mezzanine.read.get.ex
ok

$ mix compile --warnings-as-errors
exit 0

$ mix test test/mezzanine/workspace_test.exs
10 tests, 0 failures

$ rm -f /tmp/mezzanine_chassis_deployment_projection.term && mix mezzanine.workflow.dispatch chassis_materialize_deployment && mix mezzanine.read.get chassis_deployment_projection
workflow=chassis_materialize_deployment status=active receipt_ref=receipt:deployment:785b231e app_ref=app:demo:installation:acme:demo:tenant:dev outbox_delivered=1
projection=chassis_deployment_projection status=active receipt_ref=receipt:deployment:785b231e app_ref=app:demo:installation:acme:demo:tenant:dev tenant_ref=tenant:dev installation_ref=installation:acme:demo
```

* Commit: `c551de1`, pushed to `origin/main`.

## 9. Commits And Push Status

* `/home/home/p/g/n/chassis`: source commit `a053392`, pushed to `origin/main`.
* `/home/home/p/g/n/mezzanine`: sibling commit `c551de1`, pushed to
  `origin/main`.
* Report commit follows this report file.
