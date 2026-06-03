# Phase 15 Report - Observability Metrics

## 1. Scope

* Permitted package (per 0537): `observability/chassis_metrics`.
* Files touched in `observability/chassis_metrics`:
  * `lib/chassis/metrics.ex` - observability structs, emitter behaviour,
    metric catalogue, metric helpers, health-signal builder, tenant label
    partitioning, and Test/File/Console/OTel-compatible backends.
  * `mix.exs` / `mix.lock` - dependencies on `chassis_contracts`, `jason`, and
    `telemetry`.
  * Generated package marker and smoke test deleted.
  * Behavioral tests added for catalogue coverage, backend side effects,
    fail-closed validation, health signals, JSONL output, telemetry events, and
    tenant label hashing.

## 2. Test-First Evidence

* Focused tests were written before implementation and replaced the generated
  smoke test.
* Initial meaningful failure:
  * `Chassis.Contracts.IsolationProfile.__struct__/1 is undefined`, proving the
    generated package lacked the dependency and could not enforce the required
    observability-isolation label policy.
* Passing result:
  * `observability/chassis_metrics`: 7 tests, 0 failures.

## 3. Checklist Items Completed

- [x] Start-of-Phase Spine Audit - reviewed 0503 Phase 15, 0519 §5-§9, 0537,
  and `Chassis.Contracts.IsolationProfile`.
- [x] Progressive Checking.
- [x] Test-First Requirement.
- [x] `Chassis.Metrics` implements `NSHKR.Observability.Emitter`.
- [x] All 12 Phase 15 OTel-compatible metric names are present in the
  catalogue with required labels and kind/unit metadata.
- [x] `emit_health_signal/1` validates required attrs and emits real
  `NSHKR.Observability.HealthSignal` structs.
- [x] `Chassis.Metrics.Backend.OTel`, `Console`, `File`, and `Test` all perform
  observable side effects.
- [x] `tenant_ref` labels are hashed for
  `IsolationProfile.observability_isolation: :shared_redacted`.

## 4. Checklist Items Deferred Or Partial

* Cross-package instrumentation hooks are deferred because Phase 15 permits only
  `observability/chassis_metrics`. The metrics API and catalogue are ready for:
  * `Transaction.run/1`
  * `SSHBootstrap.exec_line/2`
  * `BEAMDistribution.init_node/1`
  * `HealthSupervisor`
* The deployment CLI smoke is still blocked by
  `Chassis.CLI.Command.Stack.Deploy` returning `not_implemented`, which is
  later CLI/stack-manager scope.

## 5. Execution Integrity Audit Output

```text
$ rg -n "package_smoke_test|implemented\\?\\(\\)|chassis_evolution_run_count_total|chassis_model_materialization_count_total|for backend <-|status: :accepted" observability/chassis_metrics
no generated marker/smoke/static metrics paths remain in Phase 15 source
```

## 6. Cross-Phase Invariants

* I1 PASS - source changes are limited to `observability/chassis_metrics`.
* I2 PASS - no root CLI static response path was added.
* I3 PASS - generated marker module and package smoke test deleted.
* I4 PASS - no generator scripts added.
* I5 PASS - checklist edits are line-level and tied to completed work.
* I6 PASS - behavioral tests cover helper happy paths, invalid metric atoms,
  wrong helper kinds, missing health attrs, file side effects, telemetry side
  effects, console side effects, and all-catalogue emission.
* I7 PASS - `tenant_ref` labels are partitioned/hash-redacted for shared
  observability isolation.
* I8 PASS - no production/receipt/snapshot pointer was promoted.

## 7. QC Gate Output

```text
$ (cd observability/chassis_metrics && mix test)
7 tests, 0 failures

$ (cd observability/chassis_metrics && mix format --check-formatted)
ok

$ (cd observability/chassis_metrics && mix run -e '...Chassis.Metrics.incr(... backend: {Chassis.Metrics.Backend.File, path: "/tmp/chassis_phase15_metrics.jsonl"})' && grep 'chassis.deployment.count_total' /tmp/chassis_phase15_metrics.jsonl)
JSONL record written with name "chassis.deployment.count_total" and hashed tenant_ref

$ mix monorepo.compile --warnings-as-errors
Blitz impact summary: selected=28 skipped=27 total=55
exit 0

$ mix blitz.workspace.impact test --projects chassis_metrics
FAILED: Blitz 0.3.0 CLI does not expose --projects; OptionParser rejected it.

$ mix run -e 'workspace = Blitz.MixWorkspace.load!(); Blitz.MixWorkspace.Impact.run!(workspace, :test, [], only_projects: ["observability/chassis_metrics"], force: true)'
Blitz impact summary: selected=1 skipped=0 total=1
observability/chassis_metrics: 7 tests, 0 failures

$ mix ci
FAILED in workspace format stage because of pre-existing unrelated format drift
across earlier packages. Phase 15 package format, compile, focused impact, and
metrics JSONL smoke passed.

$ mix chassis.stack.deploy --profile profile:monolith --env dev --metrics-backend File
FAILED: Chassis.CLI.Command.Stack.Deploy is still a not_implemented root CLI
command module gated for a later phase.
```

## 8. Sibling Repo Bridge Work

* Repo path: none.
* Files changed: none.
* Tests run in sibling repo: none.
* Commit hash or not-committed reason: not committed; Phase 15 required no
  sibling repo changes.

## 9. Commits And Push Status

* `~/p/g/n/chassis`: source commit `754df7b`, pushed to `origin/main`.
* Report commit follows this report file.
