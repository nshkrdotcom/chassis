# Phase 19 Report - Tenant Isolation and Residency

Date: 2026-06-03

## Scope

- Permitted primary package: `core/chassis_tenant`.
- Required integration package: `manager/chassis_stack_manager` for pre-side-effect tenant guard wiring.
- Required verification package: `core/chassis_boundary` for existing mutating envelope `tenant_ref` rejection.
- Sibling repos: none.

## Source Commits

- Chassis source commit: `6a809d3` (`Phase 19: enforce tenant residency and quota guards`), pushed to `origin/main`.
- Report commit: pending in this file's commit.

## Implemented

- Replaced placeholder tenant logic with real residency, isolation, quota, topology, observability, and quota-tracker modules.
- Added catalog fetch paths for `residency:us-only`, `residency:eu-only`, `residency:global`, tenant isolation profiles, and tenant quota profiles.
- Implemented `TopologyGuard.validate/2` with fail-closed tenant context checks, residency/provider checks, dedicated-node sharing rejection, resource quota checks, host capacity checks, and tenant label posture output.
- Implemented `QuotaGuard.check/2` using current `QuotaConsumptionTracker` usage plus requested resources, returning explicit safe admission decisions.
- Implemented `GuardSupervisor` and `QuotaConsumptionTracker` as a real supervised GenServer path.
- Wired `TopologyGuard` and `QuotaGuard` into `Chassis.StackManager.Transaction.run/1` after profile/host resolution and before authorize, provision, mesh, registry, or receipt side effects.
- Verified `Chassis.Boundary.Envelope.new!/1` already rejects mutating envelopes without `tenant_ref`; no source edit was needed in `core/chassis_boundary`.

## Tests Run

- `mix test test/tenant_guard_test.exs` in `core/chassis_tenant`: 5 tests, 0 failures before tracker test addition.
- `mix test test/tenant_guard_integration_test.exs` in `manager/chassis_stack_manager`: 3 tests, 0 failures after correction.
- `mix test` in `core/chassis_tenant`: 7 tests, 0 failures.
- `mix test` in `manager/chassis_stack_manager`: 7 tests, 0 failures.
- `mix test` in `core/chassis_boundary`: 10 tests, 0 failures.
- `mix monorepo.compile --warnings-as-errors`: passed, selected 32, skipped 23, total 55.
- `mix blitz.workspace.impact test --projects core/chassis_tenant manager/chassis_stack_manager core/chassis_boundary`: failed option parsing with `Invalid options: [{"--projects", nil}]`.
- `mix blitz.workspace.impact test --dry-run`: selected 32, skipped 23, total 55.
- `mix monorepo.test`: passed, selected 32, skipped 23, total 55.
- `mix format --check-formatted` on Phase 19 changed files: passed.
- Required CLI smoke:
  - `mix chassis.stack.deploy --profile profile:ternary-split-3 --env prod --tenant tenant:acme --residency residency:us-only --hosts test/fixtures/hosts_eu_only.json ; test $? -eq 1`
  - Overall shell exit: 0.
  - Command failure reason: Phase 20 CLI command module gate still returns `not_implemented` for `Chassis.CLI.Command.Stack.Deploy`.
- Direct transaction residency smoke in `manager/chassis_stack_manager`: passed, returning `{:error, {:topology_invalid, [%{code: :residency_violation}, ...]}}` before side effects.
- `mix ci`: failed during workspace format checking on out-of-phase pre-existing files, including `core/chassis_mesh`, `core/chassis_receipts`, `core/chassis_stack`, `bootstrap/chassis_bootstrap`, `bootstrap/chassis_doctor`, `bootstrap/chassis_installer`, `core/chassis_inventory`, `adapters/chassis_artifact_fs`, and `adapters/chassis_systemd`.

## Checklist Status

- Completed: all Phase 19 implementation bullets.
- Completed: all Phase 19 behavioral test bullets.
- Completed: Phase 19 spine audit for shared-redacted tenant labels.
- Deferred: none.

## Known Gaps

- Full `mix ci` is not green because of out-of-phase formatting drift in packages outside the Phase 19 permitted set. Phase 19 changed files pass direct format checking.
- The required `mix chassis.stack.deploy` smoke currently exits through the Phase 20 CLI `not_implemented` gate. The real Phase 19 residency enforcement is verified through StackManager unit tests and the direct transaction smoke.
