# Phase 10 Report — Secrets Plane (`chassis_secret_*`)

## 1. Scope

* Permitted packages (per 0537 §3): `secrets/chassis_secret_refs`,
  `secrets/chassis_secret_env`, `secrets/chassis_secret_sops`,
  `secrets/chassis_secret_vault`.
* Files touched:
  * `secrets/chassis_secret_refs/lib/chassis/secret_refs.ex` — real
    `SecretRef`, `SecretLease`, `MaterializationRecord`,
    `Materializer` behaviour, `LeaseSupervisor`, and lease child process.
  * `secrets/chassis_secret_env/lib/chassis/secret_env.ex` — env-var
    materializer returning real `SecretLease` values and missing-env errors.
  * `secrets/chassis_secret_sops/lib/chassis/secret_sops.ex` — SOPS
    decrypt path via `System.cmd("sops", ...)`, injected decrypt/encrypt
    boundary for tests, nested-key fetch, redaction, and `Chassis.Keys.Manager`.
  * `secrets/chassis_secret_vault/lib/chassis/secret_vault.ex` — explicit
    future adapter returning `{:error, {:not_implemented, __MODULE__}}`.
  * Four package `mix.exs` files — path/Jason deps needed for real structs
    and SOPS JSON.
  * Four package `mix.lock` files — package-local locks matching existing
    prior-phase package-lock practice.
  * Four generated marker modules and four generated smoke tests deleted.
  * Four behavioral test files added.

## 2. Test-First Evidence

* Failing tests were written first and replaced generated smoke tests.
* Initial focused run using the documented command failed before execution:
  `mix blitz.workspace.impact test --projects ...` is unsupported by the
  local Blitz task and returns `Invalid options: [{"--projects", nil}]`.
* Direct package runs then proved failures:
  * `chassis_secret_refs`: compile failures on missing `tenant_ref`, `path`,
    `key`, `redaction_policy_ref`, and `consumer_ref` fields.
  * `chassis_secret_env` / `chassis_secret_sops` / `chassis_secret_vault`:
    missing `SecretLease`/`SecretRef` deps and missing Vault `revoke/1`.
* Passing result after implementation:
  * `chassis_secret_refs`: 4 tests, 0 failures.
  * `chassis_secret_env`: 3 tests, 0 failures.
  * `chassis_secret_sops`: 4 tests, 0 failures.
  * `chassis_secret_vault`: 2 tests, 0 failures.

## 3. Checklist Items Completed

- [x] Start-of-Phase Spine Audit — reviewed 0503 Phase 10, 0510, 0537,
  0540, 0541, and `handoff_phase_09_to_10.md`.
- [x] Progressive Checking.
- [x] `chassis_secret_refs`: `Chassis.Secrets.SecretRef`, `SecretLease`,
  `MaterializationRecord` per 0510 §1, with JSON derives that exclude
  secret material.
- [x] `chassis_secret_refs`: `Chassis.Secrets.Materializer` behaviour with
  `materialize/2` and `revoke/1`.
- [x] `chassis_secret_env`: `Chassis.Secrets.Materializer.Env` per 0510 §3-A.
- [x] `chassis_secret_sops`: `Chassis.Secrets.Materializer.Sops` per 0510
  §3-B. `decrypt/2` calls `System.cmd("sops", ["--decrypt",
  "--output-type", "json", vault_path], env: ..., stderr_to_stdout: true)`.
- [x] Behavioral QC assertions: tests prove mock-boundary SOPS
  materialization returns a `SecretLease`, no plaintext temp files are
  written by the materializer, Inspect/JSON output omit private-key bytes,
  failed SOPS command output is redacted, and key-manager receipts contain
  fingerprints only.
- [x] `chassis_secret_vault`: canonical explicit future adapter.
- [x] `Chassis.Secrets.LeaseSupervisor`: DynamicSupervisor + lease process
  with self-destruct timer, authorization by `consumer_ref`, and cleanup
  callbacks.
- [x] `Inspect` impl on `SecretLease` masks `material`.
- [x] `Chassis.Keys.Manager.add/3`, `list/1`, `show/2`, `rotate/3`
  helpers mutate decrypted vault state and emit safe receipts.
- [x] `Chassis.Receipts.KeyRotationRecord` emitted for add/rotate with
  hashed fingerprint only. The existing Phase 2 struct has no `event_type`
  field, so event type remains in the manager result, not the receipt.

## 4. Checklist Items Deferred

* DEFERRED: `chassis keys.add`, `keys.list`, `keys.show`, `keys.rotate`
  command modules and stdin smoke. Reason: 0537 §3 limits Phase 10 package
  mutation to the four `secrets/chassis_secret_*` packages; `manager/chassis_cli`
  is Phase 20. Static-CLI regressions remain green and `keys.*` commands
  still return canonical `not_implemented` rather than a static success path.
* DEFERRED: live SOPS/age-key smoke. Reason: `sops` is not installed in this
  environment and no operator age key is available. The production decrypt
  command shape is tested through `cmd_runner:` injection; vault mutation is
  tested through `crypto_backend:` injection.
* DEFERRED: `/opt/nshkr` leak grep returning 1. Reason: `/opt/nshkr/receipts`
  and `/opt/nshkr/metrics` do not exist in this environment, so grep returns
  2 for missing directories. A production-source leak audit was run instead
  and only matched redaction regex code, not embedded material.

## 5. Execution Integrity Audit Output

```text
$ rg -n "implemented\?\(\)|package_smoke_test|materialized:|missing_env_secret|:not_implemented\}|\{:error, :not_implemented\}" secrets/chassis_secret_refs secrets/chassis_secret_env secrets/chassis_secret_sops secrets/chassis_secret_vault
<empty; exit 1>

$ rg -n "BEGIN.*PRIVATE KEY|password" secrets/chassis_secret_refs/lib secrets/chassis_secret_env/lib secrets/chassis_secret_sops/lib secrets/chassis_secret_vault/lib
secrets/chassis_secret_sops/lib/chassis/secret_sops.ex:15: redaction regex
secrets/chassis_secret_sops/lib/chassis/secret_sops.ex:102: redaction regex

$ grep -rEi 'BEGIN.*PRIVATE KEY|password' /opt/nshkr/receipts /opt/nshkr/metrics
grep: /opt/nshkr/receipts: No such file or directory
grep: /opt/nshkr/metrics: No such file or directory
exit 2
```

## 6. Cross-Phase Invariants

* I1 PASS — source changes limited to the four Phase 10 secrets packages
  plus this phase report.
* I2 PASS — 12/12 manager CLI static-invariant tests + 6/6 workspace-root
  CLI static-invariant tests still green.
* I3 PASS — generated marker modules and generated smoke tests deleted for
  all four activated packages.
* I4 PASS — no generator scripts added.
* I5 PASS — checklist edits are line-level and tied to completed work.
* I6 PASS — 13 new behavioral tests cover happy paths, unhappy paths,
  redaction, cleanup side effects, command-boundary contracts, and explicit
  future-adapter behavior.
* I7 PASS — secret material is excluded from `Jason.Encoder` derives,
  `Inspect`, receipts, and command error output redaction.
* I8 PASS — key-manager mutation occurs only after decrypted vault state is
  available; no failed/incomplete artifact pointer is promoted.

## 7. QC Gate Output

```text
$ mix test  # in secrets/chassis_secret_refs
4 tests, 0 failures

$ mix test  # in secrets/chassis_secret_env
3 tests, 0 failures

$ mix test  # in secrets/chassis_secret_sops
4 tests, 0 failures

$ mix test  # in secrets/chassis_secret_vault
2 tests, 0 failures

$ mix monorepo.compile --warnings-as-errors
Blitz impact summary: selected=22 skipped=33 total=55

$ mix monorepo.format --check-formatted
FAILED: Phase 10 packages were formatted and reported ok, but the full
workspace check found pre-existing formatting drift in earlier-phase
packages including bootstrap/chassis_bootstrap, bootstrap/chassis_doctor,
bootstrap/chassis_installer, core/chassis_core, core/chassis_mesh,
core/chassis_receipts, core/chassis_stack, adapters/chassis_artifact_fs,
and adapters/chassis_systemd. No unrelated formatting changes were made
in Phase 10.

$ mix test test/root_cli_static_response_path_regression_test.exs
6 tests, 0 failures

$ (cd manager/chassis_cli && mix test test/static_response_path_regression_test.exs)
12 tests, 0 failures

$ mix blitz.workspace.impact test
Blitz impact summary: selected=22 skipped=33 total=55
```

## 8. Commits And Push Status

* `~/p/g/n/chassis`: this commit. Push pending until end of phase.
* `~/p/g/j/jido_brainstorm/nshkrdotcom`: checklist commit follows after
  this source commit.
