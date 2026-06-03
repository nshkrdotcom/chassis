# Phase 14 Report - AITrace Bridge

## 1. Scope

* Permitted package (per 0537): `observability/chassis_aitrace_bridge`.
* Files touched in `observability/chassis_aitrace_bridge`:
  * `lib/chassis/aitrace/bridge.ex` - public `emit_span/3`,
    `emit_event/3`, span catalogue, required-attribute validation, exporter
    selection, dev/prod exporter defaults, and `file://` JSONL smoke support.
  * `lib/chassis/aitrace/bridge/attribute_filter.ex` - Chassis redactions on
    top of `AITrace.ExportBounds.profile/0`.
  * `lib/chassis/aitrace/bridge/exporter/jsonl.ex` - real AITrace exporter
    writing bounded span/event records as JSONL.
  * `lib/chassis/aitrace/application.ex` - package application supervisor.
  * `mix.exs` / `mix.lock` - sibling AITrace path dependency and JSON support.
  * Generated bridge, marker module, and smoke test deleted.
  * Behavioral tests added for export side effects, catalogue coverage,
    redaction, fail-closed validation, JSONL file export, and exporter config.

## 2. Test-First Evidence

* Focused tests were written before implementation and replaced the generated
  smoke test.
* Initial meaningful failure:
  * `AITrace.Trace.__struct__/1 is undefined`, proving the generated package
    lacked the sibling AITrace dependency and could not export real traces.
* Passing result:
  * `observability/chassis_aitrace_bridge`: 7 tests, 0 failures.

## 3. Checklist Items Completed

- [x] Start-of-Phase Spine Audit - reviewed 0503 Phase 14, 0519, 0537, sibling
  AITrace `ExportBounds`, `Trace`, `Span`, `Event`, and exporter APIs.
- [x] Progressive Checking.
- [x] Test-First Requirement.
- [x] `Chassis.AITrace.Bridge.emit_span/3` and `emit_event/3` build completed
  `AITrace.Trace` values and export through real AITrace exporters.
- [x] `Chassis.AITrace.Bridge.AttributeFilter` hashes raw IP addresses and raw
  BEAM node names before applying `AITrace.ExportBounds.bound_map!/2`.
- [x] All 13 Phase 14 span names are present in the package catalogue with
  required attributes validated before export.
- [x] Dev export config defaults to `AITrace.Exporter.File`; prod config can
  supply OTel-compatible exporter modules through `:otel_exporters`.
- [x] `file://...jsonl` export writes real JSONL records for CLI smoke paths.

## 4. Checklist Items Deferred Or Partial

* Cross-package hook installation is deferred because Phase 14 permits only
  `observability/chassis_aitrace_bridge`. The bridge exposes the validated
  catalogue and real export API for the following later/previous package-owned
  hooks, but Phase 14 did not modify those packages:
  * `Chassis.Receipts.DeploymentRecord.after_action`
  * `Chassis.Receipts.ProvisioningRecord.after_action`
  * `Chassis.Stack.ProfileResolver.resolve/2`
  * `Chassis.Mesh.BEAMDistribution.init_node/1`
  * `Chassis.Mesh.HealthSupervisor`
* The deployment CLI smoke is still blocked by
  `Chassis.CLI.Command.Stack.Deploy` returning `not_implemented`, which is
  later CLI/stack-manager scope.

## 5. Execution Integrity Audit Output

```text
$ rg -n "package_smoke_test|implemented\\?\\(\\)|\\{kind: kind, name: name|attrs: Chassis.AITrace|TestEmitter.*spans, do: \\[\\]|status: :accepted" observability/chassis_aitrace_bridge
no generated marker/smoke/static bridge paths remain in Phase 14 source
```

## 6. Cross-Phase Invariants

* I1 PASS - source changes are limited to `observability/chassis_aitrace_bridge`.
* I2 PASS - no root CLI static response path was added.
* I3 PASS - generated marker module and package smoke test deleted.
* I4 PASS - no generator scripts added.
* I5 PASS - checklist edits are line-level and tied to completed work.
* I6 PASS - behavioral tests cover happy path, missing required attributes,
  JSONL side effects, exporter config, catalogue contract, and sensitive data
  redaction.
* I7 PASS - raw IP addresses, raw BEAM node atoms, passwords, private keys,
  tokens, and Chassis-local sensitive fields do not appear in exported traces.
* I8 PASS - no production/receipt/snapshot pointer was promoted.

## 7. QC Gate Output

```text
$ (cd observability/chassis_aitrace_bridge && mix test)
7 tests, 0 failures

$ (cd observability/chassis_aitrace_bridge && mix format --check-formatted)
ok

$ (cd observability/chassis_aitrace_bridge && mix run -e '...emit_span("chassis.deployment.accepted", ..., export_url: "file:///tmp/chassis_phase14_aitrace.jsonl")' && grep '"chassis.deployment.accepted"' /tmp/chassis_phase14_aitrace.jsonl)
JSONL record written with name "chassis.deployment.accepted" and export_bounds schema "aitrace.export_bounds.v1"

$ mix monorepo.compile --warnings-as-errors
Blitz impact summary: selected=1 skipped=54 total=55
exit 0

$ mix blitz.workspace.impact test --projects chassis_aitrace_bridge
FAILED: Blitz 0.3.0 CLI does not expose --projects; OptionParser rejected it.

$ mix run -e 'workspace = Blitz.MixWorkspace.load!(); Blitz.MixWorkspace.Impact.run!(workspace, :test, [], only_projects: ["observability/chassis_aitrace_bridge"], force: true)'
Blitz impact summary: selected=1 skipped=0 total=1
observability/chassis_aitrace_bridge: 7 tests, 0 failures

$ mix ci
FAILED in workspace format stage because of pre-existing unrelated format drift
across earlier packages. Phase 14 package format, compile, focused impact, and
smoke export passed.

$ mix chassis.stack.deploy --profile profile:monolith --env dev --aitrace-export file:///tmp/aitrace.jsonl
FAILED: Chassis.CLI.Command.Stack.Deploy is still a not_implemented root CLI
command module gated for a later phase.
```

## 8. Sibling Repo Bridge Work

* Repo path: `/home/home/p/g/n/AITrace`
* Files changed: none.
* Tests run in sibling repo: none.
* Commit hash or not-committed reason: not committed; Phase 14 uses the
  existing sibling AITrace API through a path dependency and required no sibling
  source changes.

## 9. Commits And Push Status

* `~/p/g/n/chassis`: source commit `f6e2ea7`, pushed to `origin/main`.
* Report commit follows this report file.
