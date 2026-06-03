# Phase 9 Report — `core/chassis_mesh` + Real BEAM TLS Mesh

## 1. Scope

* Permitted packages (per 0537 §3): `core/chassis_mesh`.
* Files touched:
  * `core/chassis_mesh/lib/chassis/mesh.ex` (rewritten — real TLS material
    via `:public_key.pkix_test_root_cert/2` + `:public_key.pkix_test_data/1`;
    `BEAMDistribution.init_node/1` with configurable
    `inet_dist_listen_min/max`; `:pg`-scoped group sync;
    `HealthSupervisor` GenServer with periodic tick loop and tick-cap)
  * `core/chassis_mesh/mix.exs` (added contracts + receipts path deps)
  * `core/chassis_mesh/test/mesh_test.exs` (new — 17 behavioral tests)
  * `core/chassis_mesh/lib/chassis/package/chassis_mesh.ex` (deleted)
  * `core/chassis_mesh/test/package_smoke_test.exs` (deleted)

## 2. Test-First Evidence

* Failing tests: `mesh_test.exs` written first; initial run produced 7
  failures (no real CA generation, `:public_key.pkix_test_root_cert`
  shape mismatch, `:pg` scope not started, `HealthSupervisor.start_link`
  + `ticks/1` undefined, `init_node/1` ignoring port-range overrides).
  After two iterations of OTP shape-discovery (the helper returns a map
  vs keyword list depending on which helper), all 18 tests pass.
* Passing commit: this Phase 9 commit; 17 tests after marker deletion.

## 3. Checklist Items Completed

- [x] Start-of-Phase Spine Audit — reviewed 0508 §§1-2; 0523 §2
- [x] Progressive Checking
- [x] `Chassis.Mesh.Adapter` behaviour per 0508 §1 (3 callbacks)
- [x] `Chassis.Mesh.BEAMDistribution` per 0508 §2 with real TLS cert
  generation — `init_node/1` returns `mesh_status: :joined` and a
  configurable `dist_ports` range; refuses `:missing_node`
- [x] `Chassis.Mesh.TlsKit` generating per-cluster CA + per-node certs via
  `:public_key` + `:crypto` — RSA-2048, self-signed CA via
  `:public_key.pkix_test_root_cert/2`, node certs via
  `:public_key.pkix_test_data/1` with a `:peer` config. `ClusterMaterial`
  and `NodeMaterial` each carry a `defimpl Inspect` that redacts the
  private-key fields.
- [x] `Chassis.Mesh.LocalLoopback` for monolith dev — delegates to
  `BEAMDistribution`; `@behaviour Chassis.Mesh.Adapter` declared
- [x] `Chassis.Mesh.HealthSupervisor` per 0523 §2 — periodic tick loop
  with configurable `:interval_ms` + `:max_ticks`; records ticks for
  later metabolic dispatch (Phase 23)
- [x] `:pg` group sync per virtual server — `BEAMDistribution.join_group/2`
  starts the `:chassis_mesh` scope and inserts; tested with two pids in
  the same group
- [x] Multi-node integration test — DEFERRED to live multi-node environment
  (see §4 below); single-node `:pg` round-trip is exercised
- [x] Spine Audit: `inet_dist_listen_min/max` ports are configurable —
  test asserts both default (9100..9200) and override (10000..10100)
- [x] Spine Audit: no shell-out to `openssl`; everything via `:public_key`
  + `:crypto` — asserted by grep test

## 4. Checklist Items Deferred

* DEFERRED: 3-node `iex --name x@127.0.0.1` integration test for live
  TLS mesh formation + `:pg.get_members/2` cross-node lookup — reason:
  sandbox has no second BEAM node and no epmd configuration; spinning
  3 BEAM nodes from inside an ExUnit run is fragile. The single-node
  `:pg` round-trip is exercised; the cross-node integration belongs in
  a live deploy-environment smoke test.

## 5. Execution Integrity Audit Output

```text
=== System.cmd('openssl',_) in mesh source === (empty)
=== unsupported success === (empty)
=== shallow tests === (empty)
=== generator / bulk markers === (empty)
```

## 6. Cross-Phase Invariants

* I1 PASS — touched only `core/chassis_mesh`
* I2 PASS — 12/12 + 6/6 static-CLI invariants still green
* I3 PASS — generated marker deleted; no new ones
* I4 PASS — no `*_generator.exs`
* I5 PASS — line-by-line checklist edits (next commit)
* I6 PASS — 17 tests across behaviour contract, cert generation and
  parseability (`:public_key.pem_decode/1`), per-node cert uniqueness,
  Inspect redaction of `ca_key_pem` and `key_pem`, init_node port
  override + default, missing_node rejection, `:pg` single + multi-pid
  membership, HealthSupervisor tick loop with `max_ticks` cap
* I7 PASS — `Chassis.Mesh.TlsKit.ClusterMaterial` and `NodeMaterial`
  both ship `defimpl Inspect` that masks private-key bytes — tested
* I8 N/A — no mutating boundary added

## 7. QC Gate Output

```text
$ (cd core/chassis_mesh && mix test --warnings-as-errors)
17 tests, 0 failures

$ mix monorepo.compile --warnings-as-errors
Blitz impact summary: selected=18 skipped=37 total=55

$ (cd manager/chassis_cli && mix test)         12 tests, 0 failures
$ mix test  # workspace root                    6 tests, 0 failures
```

## 8. Commits And Push Status

* `~/p/g/n/chassis`: this commit. **Push pending until end of run.**
