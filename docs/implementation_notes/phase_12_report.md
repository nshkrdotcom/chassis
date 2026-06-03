# Phase 12 Report — Ring 0 Boundary Protocol

## 1. Scope

* Permitted package (per 0537 §3): `core/chassis_boundary`.
* Additional root workspace files touched:
  * `lib/chassis/boundary_command_bridge.ex` — root CLI command bridge for
    `mix chassis.boundary.scan` and `mix chassis.boundary.conformance`.
  * `test/root_cli_static_response_path_regression_test.exs` — proves the
    root CLI dispatches boundary commands into real package-owned logic.
* Files touched in `core/chassis_boundary`:
  * `lib/chassis/boundary.ex` — protocol behaviour, envelope, error taxonomy,
    adapters, registry, request/response/error DTOs, scan, and conformance.
  * `lib/mix/tasks/chassis_boundary_tasks.ex` — package-local Mix scan and
    conformance tasks.
  * `mix.exs` / `mix.lock` — GroundPlane codec and Chassis secret-ref deps.
  * Generated package marker and smoke test deleted.
  * Behavioral tests added for envelope validation, adapters, registry, scan,
    and conformance.

## 2. Test-First Evidence

* Focused tests were written before implementation and replaced the generated
  smoke test.
* Initial failure:
  * `Chassis.Boundary.MaterializeDeployment.Response` could not hold
    `deployment_receipt_ref`, proving the generated DTO surface was not the
    Phase 12 contract.
* Passing result:
  * `core/chassis_boundary`: 10 tests, 0 failures.
  * Root CLI static regression: 7 tests, 0 failures.

## 3. Checklist Items Completed

- [x] Start-of-Phase Spine Audit — reviewed 0503 Phase 12, 0514, 0520,
  0537, and the generated package state.
- [x] Progressive Checking.
- [x] Test-First Requirement.
- [x] `Chassis.Boundary.Protocol` behaviour per 0514 §1.
- [x] `Chassis.Boundary.Envelope` per 0514 §2 with `new!/1`,
  `response!/3`, `encode!/1`, `decode!/1`, and stable `digest/1`.
- [x] Behavioral QC assertions for rejection of raw credentials/keys, PIDs,
  unsafe atoms, `SecretLease`, missing tenant, missing authority, missing
  trace, missing envelope ref, and missing idempotency key.
- [x] `Chassis.Boundary.Error` taxonomy per 0514 §3.
- [x] `Chassis.Boundary.LocalAdapter` per 0514 §4.
- [x] `Chassis.Boundary.BeamDistributionAdapter` per 0514 §4.
- [x] `Chassis.Boundary.Registry` per 0514 §5 with exactly the 8 base
  protocol specs.
- [x] All 8 request/response/error module families per 0514 §6.
- [x] Integration with `GroundPlane.Boundary.Codec` per 0520 §2 plus Chassis
  pre-validation rejecting `SecretLease` and raw private key bytes.
- [x] `Chassis.Boundary.dispatch/2` chooser.
- [x] `mix chassis.boundary.scan` and `mix chassis.boundary.conformance`.
- [x] Spine Audit: every registered protocol has all five adapter keys,
  each either a module or explicit `nil`.

## 4. Checklist Items Deferred

* None.
* Registered `:local` adapters are explicit `nil` in Phase 12 because the
  Mezzanine/AppKit/StackLab bridge packages are later phases. Local adapter
  behavior is tested through injected protocol modules without returning an
  unsupported success payload from future bridge logic.

## 5. Execution Integrity Audit Output

```text
$ rg -n "implemented\?\(\)|package_smoke_test|term_to_binary|binary_to_term|receipt:deployment:smoke|status: :accepted" core/chassis_boundary lib/chassis/boundary_command_bridge.ex test/root_cli_static_response_path_regression_test.exs
no generated marker/smoke/static codec/static receipt paths remain in Phase 12 source
```

## 6. Cross-Phase Invariants

* I1 PASS — source changes are limited to `core/chassis_boundary` and the
  root bridge needed for the documented Phase 12 Mix tasks.
* I2 PASS — root CLI still dispatches through `Chassis.CLI.Command.*`; no
  static CLI response payload was added.
* I3 PASS — generated marker module and package smoke test deleted.
* I4 PASS — no generator scripts added.
* I5 PASS — checklist edits are line-level and tied to completed work.
* I6 PASS — behavioral tests cover happy path, unhappy path, side effects,
  adapter dispatch, codec rejection, conformance contract, and root CLI
  command routing.
* I7 PASS — secret material is rejected before serialization.
* I8 PASS — no failed/incomplete artifact pointer is promoted.

## 7. QC Gate Output

```text
$ (cd core/chassis_boundary && mix test)
10 tests, 0 failures

$ (cd core/chassis_boundary && mix format --check-formatted)
ok

$ mix test test/root_cli_static_response_path_regression_test.exs
7 tests, 0 failures

$ mix monorepo.compile --warnings-as-errors
Blitz impact summary: selected=25 skipped=30 total=55

$ mix blitz.workspace.impact test --projects chassis_boundary
FAILED: Blitz 0.3.0 CLI does not expose --projects; OptionParser rejected it.

$ mix run -e 'workspace = Blitz.MixWorkspace.load!(); Blitz.MixWorkspace.Impact.run!(workspace, :test, [], only_projects: ["core/chassis_boundary"], force: true)'
Blitz impact summary: selected=1 skipped=0 total=1
core/chassis_boundary: 10 tests, 0 failures

$ mix chassis.boundary.scan
protocol_count: 8
missing_modules:
incomplete_adapter_specs:

$ mix chassis.boundary.conformance
failed:
passed: registry.base_protocol_count, registry.modules_load, registry.adapters_explicit, codec.rejects_pid_payloads, codec.digest_stability, mutations.require_idempotency
```

## 8. Commits And Push Status

* `~/p/g/n/chassis`: source commit `00bd563`, pushed to `origin/main`.
* Report/checklist commits follow after source commit.
