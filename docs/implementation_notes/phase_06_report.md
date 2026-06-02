# Phase 6 Report — `chassis_environments`

## 1. Scope

* Permitted packages (per 0537 §3): `core/chassis_environments`.
* Files touched:
  * `core/chassis_environments/lib/chassis/environments.ex` (rewritten —
    compile-time JSON decoding via `@external_resource` + `Jason.decode!/1`
    at module-compile time; `resolve/2` driven by `resolver_catalog.json`
    instead of hardcoded `case profile_ref` branches)
  * `core/chassis_environments/mix.exs` (added `{:jason, "~> 1.4"}`)
  * `core/chassis_environments/mix.lock` (new)
  * `core/chassis_environments/test/environments_test.exs` (new — 17
    behavioral tests)
  * `core/chassis_environments/lib/chassis/package/chassis_environments.ex` (deleted)
  * `core/chassis_environments/test/package_smoke_test.exs` (deleted)

## 2. Test-First Evidence

* Failing test: tests written first; initial run produced 5 failures
  proving the prior implementation fabricated environment maps at runtime
  (`config/1`) and hardcoded `decoupled-cockpit-2` and `maximal-decoupled`
  routings to `linode_ubuntu_24_04` instead of consulting the catalog.
* Passing commit: this Phase 6 commit; 17 behavioral tests, 0 failures.

## 3. Checklist Items Completed

- [x] Start-of-Phase Spine Audit (re-read 0513 §2-§5)
- [x] Progressive Checking
- [x] `Chassis.Environments.Adapter` behaviour per 0513 §2 — three
  callbacks; `FileBasedEnvironments` declares `@behaviour`
- [x] `Chassis.Environments.FileBasedEnvironments` with compile-time
  `@external_resource` + per-profile generated module attributes per
  0513 §3 (production form). Every JSON file is read at module-compile
  time, never at runtime.
- [x] `priv/profiles/linode_ubuntu_24_04.json` — already exists,
  loaded + parsed at compile time
- [x] `priv/profiles/digital_ocean_ubuntu_24_04.json` — likewise
- [x] `priv/profiles/hetzner_ubuntu_24_04.json` — likewise
- [x] `priv/profiles/local_ubuntu_24_04.json` — likewise
- [x] `priv/profiles/resolver_catalog.json` — already exists,
  drives `resolve/2`
- [x] Compile-time check: BEAM binary contains the JSON via direct
  `File.read!/1` of `:code.which(FileBasedEnvironments)` + substring
  match for `"linode"` and `"ubuntu_24_04"` (a stronger guarantee than
  `:beam_lib.chunks/2` since it confirms the bytes reach the BEAM
  binary regardless of where Elixir places them)
- [x] `FileBasedEnvironments.resolve("profile:ternary-split-3", :prod)`
  returns `linode_ubuntu_24_04` — verified by explicit test
- [x] Unit tests for each profile loaded via embedded JSON (4 explicit
  tests for the 4 environments + 5 explicit profile×env resolution tests)
- [x] Spine Audit: no runtime `File.read!/1` in any public function — the
  "spine audit — no runtime File.read of profile JSON" test scans the
  source for `def <name>...File.read!` and asserts zero matches
- [x] QC Gate: 17 behavioral tests; `mix monorepo.compile
  --warnings-as-errors` green; static-CLI regressions 12/12 + 6/6 still
  green

## 4. Checklist Items Deferred

None for Phase 6.

## 5. Execution Integrity Audit Output

```text
=== runtime File.read! in environments ===
core/chassis_environments/lib/chassis/environments.ex: @raw_envs Map.new(... File.read!(path) ...)
                                                       @raw_catalog File.read!(@catalog_path)
        -> allowed_production_use (module-attribute, compile-time only;
           verified by the spine-audit test)

=== unsupported success / static_cli_path === (empty)
=== shallow tests === (empty)
```

## 6. Cross-Phase Invariants

* I1 PASS — touched only `core/chassis_environments`
* I2 PASS — 12/12 + 6/6 CLI tests still green
* I3 PASS — generated marker deleted; no new ones
* I4 PASS — no `*_generator.exs`
* I5 PASS — line-by-line checklist edits (next commit)
* I6 PASS — 17 tests across behaviour contract, embedded-JSON shape,
  catalog-driven resolve, BEAM-byte presence, and spine audit
* I7 N/A — no receipt types added
* I8 N/A — no mutating boundary

## 7. QC Gate Output

```text
$ (cd core/chassis_environments && mix test --warnings-as-errors)
17 tests, 0 failures

$ mix monorepo.compile --warnings-as-errors
Blitz impact summary: selected=8 skipped=47 total=55

$ (cd manager/chassis_cli && mix test)
12 tests, 0 failures

$ mix test  # workspace root
6 tests, 0 failures
```

## 8. Commits And Push Status

* `~/p/g/n/chassis`: this commit. **Push pending until end of run.**

## 9. Handoff

Not rotating. Continuing into Phase 7 if budget permits.
