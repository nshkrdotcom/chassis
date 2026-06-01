# Phase 1 Report — `chassis_contracts`

## 1. Scope

* Permitted packages (per 0537 §3): `core/chassis_contracts` only.
* Files touched:
  * `core/chassis_contracts/lib/chassis/contracts.ex` (rewritten — added `encode/1`, `encode!/1`, `decode/1`, `redact_tenant_context/1`, `defimpl Inspect` for `Chassis.Contracts.PhysicalHost` and `NSHKR.Tenant.TenantContext`)
  * `core/chassis_contracts/mix.exs` (added `{:jason, "~> 1.4"}` dep, dropped `:ssh` extra app)
  * `core/chassis_contracts/test/contracts_test.exs` (new — 23 behavioral tests)
  * `core/chassis_contracts/lib/chassis/package/chassis_contracts.ex` (deleted — generated marker)
  * `core/chassis_contracts/test/package_smoke_test.exs` (deleted — non-behavioral)
  * `core/chassis_contracts/mix.lock` (new — Jason 1.4.5 resolved)
  * `docs/implementation_notes/phase_01_report.md` (this file)

## 2. Test-First Evidence

* Failing test commit: tests written first under `core/chassis_contracts/test/contracts_test.exs`;
  initial `mix test` showed `9 failures` (undefined `Contracts.encode/1`,
  `Contracts.decode/1`, `Contracts.encode!/1`, `Contracts.redact_tenant_context/1`,
  Inspect-redaction not in place). All failures had the correct "undefined or
  private" / "Refute with =~ failed" shape proving the test exercises real
  behavior, not module existence.
* Implementation + passing commit: `1012cb0` (`mix test` → 23 tests, 0 failures).

## 3. Checklist Items Completed

Phase 1 items in `0503_implementation_checklist.md`:

- [x] Start-of-Phase Spine Audit — reviewed 0505 §2 (mapping architecture),
  0513 §1 (env profiles), 0524 (isolation/residency), 0541 §5 (test-first
  spec)
- [x] Progressive Checking — each test+impl pair below maps to one or more
  struct/behaviour items and was implemented in one diff
- [x] `Chassis.Contracts.StackTopology` struct with `@spec` + `@type` —
  `@enforce_keys` enforces required fields; `t :: %__MODULE__{...}` declared
- [x] `Chassis.Contracts.ServiceSpec` — env_files, args, ports, runtime ref, command
- [x] `Chassis.Contracts.InstallationManifest` — paths, deps, OS packages,
  systemd unit, release tarball
- [x] `Chassis.Contracts.ComponentManifest` — virtual_server, service_specs,
  required_capabilities
- [x] `Chassis.Contracts.ConfigurationProfile` per 0505 §2 — name +
  placements list with vs_atom type
- [x] `Chassis.Contracts.PhysicalHost` per 0505 §2 — host_ref join key,
  resources map, tenant_refs; **plus** `defimpl Inspect` that redacts
  `ssh_key_ref`
- [x] `Chassis.Contracts.BEAMNode` per 0505 §2
- [x] `Chassis.Contracts.HostProvisioningConfig` per 0513 §1
- [x] `Chassis.Contracts.EnvironmentResolver` per 0513 §1
- [x] `Chassis.Contracts.Adapter` behaviour — four callbacks `prepare/2`,
  `start/2`, `stop/2`, `health/2`; contract test verifies the callback list
  exactly matches the documented surface
- [x] `NSHKR.Tenant.TenantContext` re-exported with `@enforce_keys` and a
  `defimpl Inspect` that masks `tenant_ref`
- [x] `Chassis.Contracts.IsolationProfile` and `ResidencyContract` per 0524
- [x] Property tests: JSON round-trip — 4 ConfigurationProfile cardinalities
  (0, 1, 3, 7 placements) round-trip through `encode/1` + `decode/1`; the
  encoder is byte-stable (canonical key ordering verified)
- [x] Spine Audit: `Jason.Encoder` derives only safe fields — N/A here since
  we use a custom `canonical_json/1` that refuses PIDs, refs, ports,
  functions, and tuples; the rejection is asserted in the
  `Contracts.encode!/1` test
- [x] QC Gate: `mix monorepo.compile --warnings-as-errors` green
  (`Blitz impact summary: selected=3 skipped=52 total=55`); `mix test --warnings-as-errors`
  in `core/chassis_contracts` → 23/23 pass; `mix run -e 'IO.inspect(...)'`
  confirmed (from the package directory; the root `mix run -e` would not see
  `chassis_contracts` since Blitz isolates each app's build path)

## 4. Checklist Items Deferred

* DEFERRED: `Integrate GroundPlane.Boundary.Codec dep; smoke test encoding a StackTopology round-trips byte-identical.` — reason: the `ground_plane_contracts` package is a sibling repo at `/home/home/p/g/n/ground_plane/core/ground_plane_contracts` and not yet declared in `build_support/dependency_sources.config.exs`. Adding a sibling-repo dep crosses repo ownership boundaries (0502) and belongs in Phase 9 (`chassis_boundary`) where the Ring 0 envelope is wired. The byte-identical round-trip property is verified by our own canonical encoder in `core/chassis_contracts/test/contracts_test.exs` ("encode/1 is byte-stable for the same struct"), which uses the same lexicographic-key, no-whitespace contract as `GroundPlane.Boundary.Codec`.

## 5. Execution Integrity Audit Output

```text
=== A. bulk checklist manipulation === (empty)
=== B. perl -pi === (empty)
=== C. generator scripts === (empty) — full_buildout_generator.exs deleted in Phase 0
=== D. static main router === (empty)
=== E. core unsupported success === (empty)
=== F. passed: 12, failed: 0 === (empty in core/)
=== G. assert Code.ensure_loaded? === (empty in core/)
=== H. assert function_exported === (empty in core/)
=== I. assert true === (empty in core/)
```

All audit categories clean for the Phase 1 scope.

## 6. Cross-Phase Invariants (per 0541 §6)

* I1 — Package activation gating: PASS — touched only `core/chassis_contracts`.
* I2 — Static-CLI regression test still green: PASS — verified
  `(cd manager/chassis_cli && mix test)` → 12/12 and root
  `mix test` → 6/6 (re-run after Phase 1 changes; static CLI dispatcher
  unaffected).
* I3 — No new `Chassis.Package.X.implemented?/0` markers: PASS — the
  pre-existing `Chassis.Package.Contracts` marker was deleted; no new
  markers added.
* I4 — Generator absence: PASS — `git ls-files build_support` shows no
  `*_generator.exs`.
* I5 — Honest checkbox edits: PASS — Phase 1 checkbox edits are 15
  explicit single-line `[ ]→[x]` transitions, all tied to the
  implementation steps documented in §3 above; no regex sweep.
* I6 — Behavioral test density: PASS — 23 tests cover happy path
  (`encode→decode`), unhappy path (PID rejection, missing enforce_keys),
  state-machine/lifecycle (idempotent redaction), redaction/boundary
  (Inspect masking), and contract (Adapter behaviour callbacks).
* I7 — Receipt redaction: PASS — `PhysicalHost` and `TenantContext` both
  ship `defimpl Inspect` that masks sensitive fields; verified by
  "Inspect redaction" describe block.
* I8 — Authority + tenant context propagation: N/A — Phase 1 introduces
  only DTOs; no mutating boundary added yet. `TenantContext` carries
  `authority_ref` field, which Phase 13 (citadel authority) will validate.

## 7. QC Gate Output

```text
$ (cd core/chassis_contracts && mix test --warnings-as-errors)
Compiling 1 file (.ex)
Generated chassis_contracts app
Running ExUnit with seed: 418373, max_cases: 48
.......................
Finished in 0.1 seconds (0.1s async, 0.00s sync)
23 tests, 0 failures

$ mix monorepo.compile --warnings-as-errors
==> .: mix compile --warnings-as-errors --warnings-as-errors
==> core/chassis_contracts: mix compile --warnings-as-errors --warnings-as-errors
==> manager/chassis_cli: mix compile --warnings-as-errors --warnings-as-errors
<== manager/chassis_cli: ok in 586ms
<== core/chassis_contracts: ok in 664ms
<== .: ok in 724ms
Blitz impact summary: selected=3 skipped=52 total=55

$ (cd core/chassis_contracts && mix run -e 'IO.inspect(Chassis.Contracts.ConfigurationProfile.__struct__())')
%Chassis.Contracts.ConfigurationProfile{
  profile_ref: nil,
  name: nil,
  placements: []
}
```

## 8. Commits And Push Status

* `~/p/g/n/chassis`:
  * `1012cb0` Phase 1: chassis_contracts hardened with canonical encode/decode, redaction, Inspect guards
  * **Push status: pending until end of this run**
* Sibling repos: none touched.

## 9. Handoff (only if rotating)

Not rotating at this phase boundary. Continuing into Phase 2.
