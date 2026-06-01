# Phase 3 Report — `chassis_inventory`

## 1. Scope

* Permitted packages (per 0537 §3): `core/chassis_inventory` only.
* Files touched:
  * `core/chassis_inventory/lib/chassis/inventory.ex` (rewritten — added
    `CapacityMap.available/1`, `allocate/2`, `release/2`; added `disk_unavailable`
    check; reworked `DynamicDiscovery` so it no longer silently falls through
    to the static fixture; every provider returns canonical not_implemented)
  * `core/chassis_inventory/mix.exs` (added `{:jason, "~> 1.4"}`)
  * `core/chassis_inventory/mix.lock` (new)
  * `core/chassis_inventory/test/inventory_test.exs` (new — 25 behavioral tests)
  * `core/chassis_inventory/lib/chassis/package/chassis_inventory.ex` (deleted)
  * `core/chassis_inventory/test/package_smoke_test.exs` (deleted)
  * `docs/implementation_notes/phase_03_report.md` (this file)

## 2. Test-First Evidence

* Failing test: `inventory_test.exs` written first; initial run failed
  because `CapacityMap.available/1`, `allocate/2`, `release/2` did not exist,
  `disk_unavailable` was not a recognized rejection, `StaticDiscovery` did
  not read a JSON path, and `DynamicDiscovery.*` returned `{:ok, fixture}`
  instead of the canonical not_implemented tuple.
* Implementation + passing: this Phase 3 commit; 25 tests, 0 failures.

## 3. Checklist Items Completed

Phase 3 items in `0503_implementation_checklist.md`:

- [x] Start-of-Phase Spine Audit — re-read 0508 §4 (Discovery behaviour),
  §5 (StaticDiscovery JSON path), §6 (DynamicDiscovery provider table)
- [x] Progressive Checking
- [x] `Chassis.Inventory.PhysicalHost` with tenant_ref filter support
- [x] `Chassis.Inventory.CapacityMap` tracking CPU, GPU, memory, disk per
  host with allocated/total fields — plus real `available/1`, `allocate/2`,
  and `release/2` transitions
- [x] Placement constraint validator: `Chassis.Inventory.PlacementValidator.check/2`
  with `:gpu_unavailable`, `:cpu_unavailable`, `:memory_unavailable`,
  `:disk_unavailable` rejection reasons
- [x] `Chassis.Inventory.Discovery` behaviour per 0508 §4 (one callback,
  `discover_hosts/1`)
- [x] `Chassis.Inventory.StaticDiscovery` per 0508 §5 reading the
  configured JSON path (default `~/.config/chassis/hosts.json`); honors
  `tenant_ref:` filter; rejects malformed JSON and missing files with
  structured `:enoent` / `{:json_decode, _}` errors
- [x] `Chassis.Inventory.DynamicDiscovery` per 0508 §6 with per-provider
  modules (`Linode`, `DigitalOcean`, `Hetzner`, `RunPod`, `VastAi`) — every
  provider returns `{:error, {:not_implemented, __MODULE__}}` per 0541 §1
  row 4 and the activation note in 0537 §3 Phase 8. The facade refuses to
  silently fall through to the static fixture and returns
  `{:error, :missing_provider}` when no provider is supplied
- [x] GPU inventory schema: `Chassis.Inventory.GpuInventory` (vendor,
  model, vram_gb, free_count)
- [x] Tenant filter: `discover_hosts(tenant_ref: ...)` returns only hosts
  tagged to that tenant — proved by the "tenant_ref filter returns only
  matching hosts" test
- [x] Property tests: 100 random hosts × 100 random requests, the
  placement validator never admits a violation — proved by the
  `:rand.seed/2`-driven loop in the placement describe block
- [x] Spine Audit: confirmed `host_ref` is the canonical join key in
  every test that lists hosts ("host_ref is the canonical join key (no
  IP-based join)")
- [x] QC Gate: 25 tests pass; `mix monorepo.compile --warnings-as-errors`
  green; static-CLI regression tests remain 12/12 and 6/6

## 4. Checklist Items Deferred

* DEFERRED: Real HTTP clients for the 5 dynamic-discovery providers —
  reason: activated in Phase 8 per 0537 §3. The placeholder modules return
  `{:error, {:not_implemented, __MODULE__}}` and are covered by per-provider
  tests asserting that exact shape.

## 5. Execution Integrity Audit Output

```text
=== unsupported success in core/chassis_inventory/lib === (empty)
=== generator / bulk markers === (empty)
=== shallow tests in core/chassis_inventory === (empty)
=== {:ok, fixture()} fall-through in DynamicDiscovery === (empty; replaced with explicit not_implemented + missing_provider)
```

## 6. Cross-Phase Invariants

* I1 — Package activation gating: PASS (touched only chassis_inventory).
* I2 — Static-CLI regression: PASS (12/12 manager + 6/6 root).
* I3 — No new markers: PASS.
* I4 — Generator absence: PASS.
* I5 — Honest checkbox edits: PASS (12 line-level edits enumerated below).
* I6 — Behavioral test density: PASS (25 tests across constructors,
  validator happy/unhappy paths, lifecycle on `CapacityMap`, JSON IO
  errors, and provider not_implemented contract).
* I7 — Receipt redaction: N/A (no new receipt types).
* I8 — Authority + tenant context propagation: PASS via tenant_ref filter
  end-to-end test on `StaticDiscovery`.

## 7. QC Gate Output

```text
$ (cd core/chassis_inventory && mix test --warnings-as-errors)
25 tests, 0 failures

$ mix monorepo.compile --warnings-as-errors
Blitz impact summary: selected=1 skipped=54 total=55

$ (cd manager/chassis_cli && mix test)
12 tests, 0 failures

$ mix test  # workspace root
6 tests, 0 failures
```

## 8. Commits And Push Status

* `~/p/g/n/chassis`: this commit. **Push status: pending until end of this run.**

## 9. Handoff

Not rotating. Continuing into Phase 4 if budget permits, otherwise stopping
at this clean phase boundary with all CLI invariants green and three
foundational packages (contracts, receipts, inventory) hardened.
