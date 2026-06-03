# Phase 31 Report - Host Daemon Socket Routing

Date: 2026-06-03

## Scope

- Package map scope: `host/chassis_host_daemon`.
- Existing package changed: `host/chassis_host_daemon`.
- Source commit: `3f52bacda5b979b8e3d6cb0bda344066fcc13dc3`.
- Sibling repo bridge work: none.
- `core/chassis_boundary` and `Chassis.Boundary.UnixSocketAdapter` were not
  changed because Phase 31 package-map scope permits only
  `host/chassis_host_daemon`. The core Unix-socket adapter work is deferred.

## Implemented

- Replaced generated host-daemon stubs with a real package-local routing surface:
  `Chassis.Host.Daemon.status/1` and `route/2`.
- Added Unix-socket frame helpers with a 4-byte big-endian length prefix and
  safe external-term decoding.
- Added peer UID ACL enforcement through `Chassis.Host.Daemon.Identity`.
- Added `Chassis.Host.Daemon.AuthCache` for local Citadel authority snapshots.
- Added `Chassis.Host.Daemon.Auth` to re-verify each envelope against
  `Chassis.Policy.Boundary.assert_mutation_authorized/1`, local authority
  snapshot outcome, and snapshot TTL.
- Added `Chassis.Host.Daemon.IdempotencyTable` and router idempotency replay so
  repeated envelopes return the cached result without re-running side effects.
- Added package-local Mix tasks:
  `mix chassis.host.daemon.status --json` and
  `mix chassis.host.daemon.socket.check --json`.
- Added `priv/systemd/nshkr-chassis-host.service` with the host daemon user,
  group, runtime directory, socket path environment, and restart posture.

## Test-First Evidence

- Initial Phase 31 tests failed because generated host-daemon support modules
  only exposed `check/1`, the package had no `Chassis.Boundary.Error`
  dependency, and router/auth/idempotency/socket behavior was absent.
- The failing tests covered socket framing, unsafe/incomplete decode errors, peer
  UID rejection, stale and denied authority snapshots, idempotent replay, router
  dispatch, status posture, and systemd unit content.
- Implementation added real operational logic and path dependencies to satisfy
  those tests without static CLI responses.

## Verification

- `cd host/chassis_host_daemon && mix deps.get`: passed.
- `cd host/chassis_host_daemon && mix format`: passed.
- `cd host/chassis_host_daemon && mix test`: 6 tests, 0 failures.
- `cd host/chassis_host_daemon && mix format --check-formatted`: passed.
- `cd host/chassis_host_daemon && mix compile --warnings-as-errors`: passed.
- `cd host/chassis_host_daemon && mix deps.tree`: passed; dependency tree
  includes `chassis_boundary`, `chassis_policy_boundary`, and `jason`.
- Direct smoke:
  `cd host/chassis_host_daemon && mix chassis.host.daemon.status --json | jq -r '.state'`
  returned `running`.
- Direct smoke:
  `cd host/chassis_host_daemon && mix chassis.host.daemon.socket.check --json | jq -r '.socket_mode'`
  returned `0660`.
- Grep audit for `0660`, `nshkr_chassis_host`, `authorize_peer`,
  `allowed_uids`, `AuthCache`, `authority snapshot`, `IdempotencyTable`,
  `encode_frame`, and `decode_frame` showed the checks in the host-daemon
  package tests, source, Mix tasks, and systemd unit.
- `mix monorepo.compile --warnings-as-errors`: passed, selected 46 skipped 9
  total 55.
- `mix monorepo.test`: passed, selected 46 skipped 9 total 55.

## Failed / Deferred Checks

- `mix blitz.workspace.impact test --projects chassis_host_daemon` failed before
  execution with Blitz option parsing:
  `** (Mix) Invalid options: [{"--projects", nil}]`.
- `mix ci` failed during workspace format checks on pre-existing out-of-phase
  formatting drift outside Phase 31. The Phase 31 package passed package-local
  format, compile, tests, and smoke checks.
- Exact manager-binary smoke
  `./chassis host.daemon status --json | jq '.state'` is deferred because
  post-Phase-20 CLI extension is package-local/disabled. The package-local Mix
  task smoke used real package logic and returned `running`.
- Direct privileged AF_UNIX binding and kernel `SO_PEERCRED` extraction are
  deferred. The completed safe subset enforces injectable peer UID maps and
  records the systemd socket/user posture without opening a privileged system
  socket during tests.
- `Chassis.Boundary.UnixSocketAdapter` remains deferred because core boundary
  edits are outside the Phase 31 package-map scope.

## Generated Artifacts

- `_build/` and `deps/` were generated during verification and are ignored/not
  committed.
- `.blitz/test_state_v1/indexes/task_states.ndjson` changed during monorepo/CI
  commands and was restored before commits.
