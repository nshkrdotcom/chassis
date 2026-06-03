# Phase 13 Report - Policy Boundary

## 1. Scope

* Permitted package (per 0537): `core/chassis_policy_boundary`.
* Files touched in `core/chassis_policy_boundary`:
  * `lib/chassis/policy_boundary.ex` - Citadel authority gate, helper modules,
    default authority provider, CLI/workflow acquisition helpers, and authority
    audit propagation helper.
  * `mix.exs` / `mix.lock` - dependencies on `chassis_boundary`,
    `citadel_governance`, and `citadel_authority_contract`.
  * Generated package marker and smoke test deleted.
  * Behavioral tests added for happy path, fail-closed paths, helper contracts,
    side-effect gating, and authority reference propagation.

## 2. Test-First Evidence

* Focused tests were written before implementation and replaced the generated
  smoke test.
* Initial meaningful failure:
  * `Chassis.Boundary.Envelope.__struct__/1 undefined`, proving the generated
    package lacked the Phase 13 dependency and could not authorize boundary
    envelopes.
* Passing result:
  * `core/chassis_policy_boundary`: 6 tests, 0 failures.

## 3. Checklist Items Completed

- [x] Start-of-Phase Spine Audit - reviewed 0503 Phase 13, 0518, 0537, and
  sibling Citadel compiler/contract modules.
- [x] Progressive Checking.
- [x] Test-First Requirement.
- [x] `Chassis.Policy.Boundary.authorize/1` compiles Citadel
  `AuthorityDecision.V1` packets through
  `Citadel.ExecutionGovernanceCompiler.compile!/4`.
- [x] Boundary/topology intent helpers build real `Citadel.BoundaryIntent` and
  `Citadel.TopologyIntent` structs.
- [x] CLI/workflow authority helpers build provider requests and return real
  `AuthorityDecision.V1` packets or fail-closed boundary errors.
- [x] Denied, unavailable, stale, timeout, invalid input, and compiler raise
  paths return `Chassis.Boundary.Error` without success payloads.
- [x] `authorize_then/2` prevents Chassis side effects before successful
  authority.
- [x] `AuthorityAudit.round_trip/3` propagates `authority_ref` through envelope,
  receipt attrs, and effect-log attrs.

## 4. Checklist Items Deferred Or Partial

* Sibling Citadel bridge: the current sibling package exposes packet modules
  and `Citadel.ExecutionGovernanceCompiler.compile!/4`, but does not expose a
  `Citadel.AuthorityContract.authorize/1` facade. The Phase 13 default provider
  delegates to that facade when present and otherwise constructs a real
  `AuthorityDecision.V1` through the contract-owned constructor. No sibling repo
  files were changed.
* Full dispatch-to-receipt E2E is helper-level in Phase 13. Real receipt
  persistence, Mezzanine effect logging, and stack CLI dispatch are owned by
  later active packages, so Phase 13 does not modify them early.

## 5. Execution Integrity Audit Output

```text
$ rg -n "package_smoke_test|implemented\\?\\(\\)|authority:decision:smoke|status: :accepted" core/chassis_policy_boundary
no generated marker/smoke/static success paths remain in Phase 13 source
```

## 6. Cross-Phase Invariants

* I1 PASS - source changes are limited to `core/chassis_policy_boundary`.
* I2 PASS - no root CLI static response path was added.
* I3 PASS - generated marker module and package smoke test deleted.
* I4 PASS - no generator scripts added.
* I5 PASS - checklist edits are line-level and tied to completed work.
* I6 PASS - behavioral tests cover happy path, denied/unavailable/stale/
  timeout/compiler-raise unhappy paths, side-effect gating, helper contracts,
  and authority reference propagation.
* I7 PASS - no secrets, indexes, runtime state, or generated artifacts were
  written into source.
* I8 PASS - no production/receipt/snapshot pointer was promoted.

## 7. QC Gate Output

```text
$ (cd core/chassis_policy_boundary && mix test)
6 tests, 0 failures

$ (cd core/chassis_policy_boundary && mix format --check-formatted)
ok

$ mix monorepo.compile --warnings-as-errors
Blitz impact summary: selected=26 skipped=29 total=55
exit 0

$ mix blitz.workspace.impact test --projects chassis_policy_boundary
FAILED: Blitz 0.3.0 CLI does not expose --projects; OptionParser rejected it.

$ mix run -e 'workspace = Blitz.MixWorkspace.load!(); Blitz.MixWorkspace.Impact.run!(workspace, :test, [], only_projects: ["core/chassis_policy_boundary"], force: true)'
Blitz impact summary: selected=1 skipped=0 total=1
core/chassis_policy_boundary: 6 tests, 0 failures

$ mix ci
FAILED in workspace format stage because of pre-existing unrelated format drift
across earlier packages. Phase 13 package format, compile, and focused tests
passed.

$ mix chassis.stack.deploy --profile profile:monolith --env dev --tenant tenant:acme --dry-run --emit-authority-decision
FAILED: Chassis.CLI.Command.Stack.Deploy is still a not_implemented root CLI
command module gated for a later phase. Phase 13 did not modify
manager/chassis_cli.
```

## 8. Sibling Repo Bridge Work

* Repo path: `/home/home/p/g/n/citadel`
* Files changed: none.
* Tests run in sibling repo: none.
* Commit hash or not-committed reason: not committed; no sibling source changes
  were required or permitted for Phase 13.

## 9. Commits And Push Status

* `~/p/g/n/chassis`: source commit `f54da30`, pushed to `origin/main`.
* Report commit follows this report file.
