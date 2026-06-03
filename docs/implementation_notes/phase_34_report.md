# Phase 34 Report - AppKit Evolution Surface

Date: 2026-06-03

## Scope

- Package map scope: integrations, no new Chassis leaf package.
- Existing Chassis package changed: `governance/chassis_appkit_surface`.
- Sibling repo bridge work: `/home/home/p/g/n/app_kit/bridges/chassis_bridge`.
- Chassis source commit: `893887753e1774db65a9adaacfe10219432b14e4`.
- AppKit bridge commit: `65615863aba9dbfeebc194d30503f58b40114d7d`.

## Implemented

- Added Chassis-side EvolutionSurface schema and behaviour metadata under
  `Chassis.AppKit.Surface.Evolution`.
- Added product-safe Chassis structs for `SurfaceError`, `RedactedDiffRef`,
  `ScoreSummary`, and `CandidateSummary`.
- Added candidate DTO construction that drops raw diff, prompt, transcript,
  provider payload, credential, secret, and state-volume path fields before the
  public DTO is built.
- Replaced the AppKit evolution placeholder with the eight callbacks from the
  Phase 34 spec:
  `list_evolution_batches/3`, `get_evolution_batch/3`,
  `get_evolution_status/3`, `get_candidate_summary/3`,
  `get_trial_summary/3`, `request_candidate_promotion/4`,
  `record_operator_consent/4`, and `get_swap_status/3`.
- Added `AppKit.EvolutionSurface.Server` and
  `AppKit.EvolutionSurface.Application`.
- Added concrete AppKit backends:
  `AppKit.EvolutionSurface.Backend.Local`,
  `AppKit.EvolutionSurface.Backend.Boundary`, and
  `AppKit.EvolutionSurface.Backend.Standalone`.
- Added AppKit DTOs under `AppKit.Core.Evolution.DTO.*`, plus
  `AppKit.Core.Evolution.SurfaceError` and `RedactedDiffRef`.
- Added explicit backend resolution through `AppKit.BackendConfig.resolve/4`.
- Added consent recording that emits
  `mezzanine.signal.chassis.evolution.consent.v1` through an injected signal
  dispatcher and returns an `OperatorConsentResult`.
- Added fail-closed raw-diff behavior for the legacy `get_candidate_diff/3`
  entrypoint.

## Test-First Evidence

- Initial Chassis tests failed to compile because
  `Chassis.AppKit.Surface.Evolution.RedactedDiffRef` was undefined.
- Initial AppKit tests failed to compile because
  `AppKit.Core.Evolution.DTO.EvolutionBatchPage` was undefined.
- Final tests cover backend injection through `BackendConfig.resolve/4`,
  raw-diff redaction without a lower-read lease, agent-context lower-read lease
  rejection, consent signal emission, schema callback inventory, and Chassis DTO
  fail-closed validation.

## Sibling Repo Bridge Work

- Repo path: `/home/home/p/g/n/app_kit`.
- Files changed:
  - `bridges/chassis_bridge/lib/app_kit/evolution_surface.ex`
  - `bridges/chassis_bridge/lib/app_kit/evolution_surface/application.ex`
  - `bridges/chassis_bridge/lib/app_kit/evolution_surface/backend.ex`
  - `bridges/chassis_bridge/lib/app_kit/evolution_surface/backend/boundary.ex`
  - `bridges/chassis_bridge/lib/app_kit/evolution_surface/backend/local.ex`
  - `bridges/chassis_bridge/lib/app_kit/evolution_surface/backend/standalone.ex`
  - `bridges/chassis_bridge/lib/app_kit/evolution_surface/dtos.ex`
  - `bridges/chassis_bridge/lib/app_kit/evolution_surface/server.ex`
  - `bridges/chassis_bridge/test/chassis_bridge_test.exs`
  - `bridges/chassis_bridge/test/evolution_surface_test.exs`
- Tests run in sibling repo:
  - `cd bridges/chassis_bridge && mix format --check-formatted`: passed.
  - `cd bridges/chassis_bridge && mix compile --warnings-as-errors`: passed.
  - `cd bridges/chassis_bridge && mix test`: 10 tests, 0 failures.
  - `cd /home/home/p/g/n/app_kit && mix run -e '<RequestContext smoke>'`:
    returned `{:ok, %AppKit.Core.Evolution.DTO.EvolutionBatchPage{...}}`.
  - `cd /home/home/p/g/n/app_kit && mix ci`: failed in unrelated
    database-backed workspace packages due Postgres connection pool exhaustion.
- Commit hash: `65615863aba9dbfeebc194d30503f58b40114d7d`, pushed.

## Verification

- `cd governance/chassis_appkit_surface && mix format`: passed.
- `cd governance/chassis_appkit_surface && mix compile --warnings-as-errors`:
  passed.
- `cd governance/chassis_appkit_surface && mix test`: 7 tests, 0 failures.
- `cd /home/home/p/g/n/chassis && mix monorepo.compile --warnings-as-errors`:
  passed, selected 48 skipped 7 total 55.
- `cd /home/home/p/g/n/chassis && mix blitz.workspace.impact test --projects chassis_appkit_surface`:
  failed before execution with Blitz option parsing:
  `** (Mix) Invalid options: [{"--projects", nil}]`.
- Runtime mutation audit:
  `rg -n "Application\\.put_env\\(:app_kit" bridges/chassis_bridge/lib bridges/chassis_bridge/test`
  returned zero matches.
- Raw-field audit showed raw/private field names only in denylist/drop logic and
  negative tests; DTO structs expose `RedactedDiffRef` rather than raw diff
  bytes.

## Failed / Deferred Checks

- Required AppKit `mix ci` failed outside Phase 34 bridge code in existing
  database-backed workspace packages:
  `core/installation_surface`, `core/review_surface`, and
  `bridges/mezzanine_bridge` hit Postgres connection exhaustion and sandbox
  checkout failures while starting `mezzanine_config_registry`.
- The literal checklist smoke uses a non-existent `ctx()` helper. The executed
  smoke used a valid `AppKit.Core.RequestContext` with a W3C-format trace ID and
  returned the expected `EvolutionBatchPage`.
- Required Blitz impact `--projects` command failed at option parsing before
  tests could run; package-local tests were used for focused verification.

## Generated Artifacts

- `_build/` and `deps/` were generated during verification and are ignored/not
  committed.
- `.blitz/test_state_v1/indexes/task_states.ndjson` changed during monorepo/CI
  commands in both Chassis and AppKit and was restored before commits.
