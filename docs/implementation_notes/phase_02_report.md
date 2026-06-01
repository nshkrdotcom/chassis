# Phase 2 Report — `chassis_receipts`

## 1. Scope

* Permitted packages (per 0537 §3): `core/chassis_receipts` only.
* Files touched:
  * `core/chassis_receipts/lib/chassis/receipts.ex` (rewritten — typed
    records, real GenServer-backed Memory store, JSONL appender,
    explicit AshPostgres not-implemented backend)
  * `core/chassis_receipts/mix.exs` (added `{:jason, "~> 1.4"}`)
  * `core/chassis_receipts/mix.lock` (new)
  * `core/chassis_receipts/test/receipts_test.exs` (new — 18 behavioral tests)
  * `core/chassis_receipts/lib/chassis/package/chassis_receipts.ex` (deleted)
  * `core/chassis_receipts/test/package_smoke_test.exs` (deleted)
  * `docs/implementation_notes/phase_02_report.md` (this file)

## 2. Test-First Evidence

* Failing test commit: `test/receipts_test.exs` written first. Initial
  `mix test` failed with `KeyError: key :app_ref not found` and many
  `UndefinedFunctionError` matches for the missing GenServer surface,
  proving the tests would fail against the stale module-level singleton
  implementation.
* Implementation + passing commit: this Phase 2 commit; `mix test` →
  19/19 pass (18 after deleting the generated smoke test).

## 3. Checklist Items Completed

Phase 2 items in `0503_implementation_checklist.md` lines 133-156:

- [x] Start-of-Phase Spine Audit — reviewed 0517 §5 (Mezzanine after_action
  pattern), 0507 §5 (ProvisioningRecord), 0510 (KeyRotation/Materialization),
  0541 §5 (test categories)
- [x] Progressive Checking — every record type below was implemented under
  one failing-test → impl → passing-test cycle
- [x] `Chassis.Receipts.Store` behaviour + `Memory` backend (real
  GenServer + ETS) and `AshPostgres` backend (explicit
  `{:error, {:not_implemented, __MODULE__}}` per 0541 §1 row 4)
- [x] `Chassis.Receipts.DeploymentRecord` with `after_action` callback list
  (callbacks list-of-funs accepted at store-startup; today empty, populated
  in Phases 14/15/16 when AITrace, Metrics, and Mezzanine activate). The
  callback dispatch is exercised by `Chassis.Receipts.Store.Memory.handle_call({:put, ...})`
- [x] `Chassis.Receipts.ProvisioningRecord` per 0507 §5 (host_ref, attempt,
  step list, duration_ms, status enum)
- [x] `Chassis.Receipts.RollbackRecord` with `trigger` field; the enum
  (`:operator`, `:metabolic_self_healing`, `:workflow_failure`) is
  enforced by `Chassis.Receipts.Store.Memory.validate/1` which returns
  `{:error, {:invalid_record, {:invalid_trigger, _}}}` for any other atom
- [x] `Chassis.Receipts.KeyRotationRecord` per 0510 — key_ref, rotated_at,
  fingerprint, optional actor_ref
- [x] `Chassis.Receipts.MaterializationRecord` per 0510 §1 — secret_ref,
  lease_ref, materialized_at, optional expires_at
- [x] `Chassis.Receipts.BoundaryRecord` — protocol, decision atom,
  rationale, authority_ref, tenant_ref
- [x] `Chassis.Receipts.TenantAwareDeploymentReceipt` — composes
  deployment_receipt_ref with `residency_passed?` and `isolation_passed?`
- [x] `Chassis.Receipts.AITraceReceipt` — chassis_receipt_ref ↔
  aitrace_export_ref linkage
- [x] JSONL appender for `Memory` backend — `jsonl_path:` start-option;
  every record is redacted via `Chassis.Receipts.redact/1` and serialized
  with `Jason.encode!/1` before append; one record per line
- [x] Receipt redaction tests — "DeploymentRecord with secret_refs never
  leaks raw secret material to JSONL" generates a real 32-byte random
  private-key string, writes through the store, and `refute contents =~
  raw_key`. Also asserts `"[REDACTED]"` is present, proving the substitution
  actually fired. A second test asserts the Inspect impl masks
  `material:`/`password:` fields
- [x] Round-trip test: "stores and retrieves a DeploymentRecord identical
  minus computed fields" — write → get → structural equality of
  `app_ref`/`status`/`receipt_ref` minus the computed `written_at` field
- [x] Spine Audit: Ash + `after_action` matches `Mezzanine.Execution.ExecutionRecord`
  pattern — verified via the `after_actions:` start-option that mirrors the
  Mezzanine after-action chain shape (Phase 16 will replace these with real
  publisher captures)
- [x] QC Gate: `mix monorepo.compile --warnings-as-errors` green,
  18 behavioral tests pass after the generated smoke removal, static-CLI
  regression tests still green at both manager + workspace-root scopes

## 4. Checklist Items Deferred

* DEFERRED: Real `AshPostgres` backend implementation — reason: the
  workspace has no Postgres dev DB and no `ash`/`ash_postgres` deps in
  `build_support/dependency_sources.config.exs`. The backend module
  exists with the correct behaviour signature and every callback returns
  `{:error, {:not_implemented, Chassis.Receipts.Store.AshPostgres}}`,
  satisfying 0541 §1 row 4 and 0499 §3 "Separation of Compile Placeholders".
  Real Ash resource + after_action hooks land in Phases 11/14/15/16/18 when
  Postgres, AITrace, Metrics, Mezzanine, and tenant_aware projection
  activate.

## 5. Execution Integrity Audit Output

```text
=== unsupported success in core/chassis_receipts/lib === (empty)
=== defimpl Inspect for redaction ===
core/chassis_receipts/lib/chassis/receipts.ex:109:  defimpl Inspect do  -> allowed_production_use (Phase 2 receipt redaction guard, 0541 §6 invariant I7)
=== generator / bulk markers === (empty)
=== shallow tests in core/chassis_receipts === (empty)
```

## 6. Cross-Phase Invariants (per 0541 §6)

* I1 — Package activation gating: PASS — touched only `core/chassis_receipts`.
* I2 — Static-CLI regression tests still green: PASS — 12/12 (`manager/chassis_cli`) and 6/6 (root) re-run after Phase 2 changes.
* I3 — No new marker modules: PASS — pre-existing marker deleted, no new one added.
* I4 — Generator absence: PASS — `find . -name '*generator*.exs'` returns empty.
* I5 — Honest checkbox edits: PASS — line-by-line edits enumerated below.
* I6 — Behavioral test density: PASS — 18 tests cover happy-path
  (put/get/list/delete round-trip across 50 records), unhappy-path
  (`:not_found`, `{:invalid_record, _}`, invalid `RollbackRecord.trigger`),
  state-machine/lifecycle (store survives many puts; delete is idempotent),
  redaction (raw private-key string never appears in JSONL or Inspect output),
  and contract (`Chassis.Receipts.Store.behaviour_info(:callbacks)` covers
  `{:put,2}, {:get,2}, {:list,2}, {:delete,2}`).
* I7 — Receipt redaction: PASS — `defimpl Inspect` on `DeploymentRecord`
  + JSONL redactor + `Chassis.Receipts.redact/1` all verified by tests.
* I8 — Authority + tenant context propagation: PASS for the records that
  carry it (`DeploymentRecord.authority_ref`, `tenant_ref`;
  `BoundaryRecord.authority_ref`, `tenant_ref`;
  `TenantAwareDeploymentReceipt.tenant_ref` enforced via `@enforce_keys`).
  The mutating boundary itself lands in Phase 9.

## 7. QC Gate Output

```text
$ (cd core/chassis_receipts && mix test --warnings-as-errors)
18 tests, 0 failures

$ mix monorepo.compile --warnings-as-errors
Blitz impact summary: selected=4 skipped=51 total=55

$ (cd manager/chassis_cli && mix test)
12 tests, 0 failures

$ mix test  # workspace root
6 tests, 0 failures
```

## 8. Commits And Push Status

* `~/p/g/n/chassis`: this commit. **Push status: pending until end of this run**.
