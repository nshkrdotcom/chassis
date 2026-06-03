# Phase 30 Report - Citadel Promotion Authority and Consent Binding

Date: 2026-06-03

## Scope

- Package map scope: Phase 30 integration phase, no new packages.
- Existing packages changed: `core/chassis_policy_boundary`,
  `evolution/chassis_evolution_receipts`.
- Source commit: `7f1e8f20b42a44febda12638523a13efe308da8b`.
- Sibling repo bridge work: none. The existing Citadel compiler and contract
  packages were consumed through `chassis_policy_boundary`; no Citadel repo files
  were changed because the package map did not permit new package work.

## Implemented

- Added the 13 Phase 30 Citadel authority intents to
  `Chassis.Policy.Boundary`, including binding-key catalog entries for evolution,
  host-daemon, model, and hardware authority refs.
- Added request-level `authorize_intent/2` that normalizes binding attrs, compiles
  real `Citadel.ExecutionGovernance.V1` packets through the existing Citadel
  compiler path, and returns the derived `authority_ref`.
- Added binding digest synthesis for evidence refs and hardware capability maps.
- Added promotion consent validation before `promote_candidate` authority
  compilation, including missing-ref and TTL-denial paths.
- Added `assert_mutation_authorized/1` to fail closed when mutation runs without
  `authority_ref` and when swap/promotion consent is absent or equal to the
  authority ref.
- Added `Chassis.Evolution.Consent` for `OperatorConsentRecord` creation,
  receipt-store persistence, bounded-summary redaction, approval checks,
  actor-kind checks, candidate/ref binding, and TTL validation.

## Test-First Evidence

- Initial Phase 30 tests failed because `authority_intents/0`,
  `binding_keys/1`, `authorize_intent/2`, `assert_mutation_authorized/1`, and
  `Chassis.Evolution.Consent` were undefined.
- A compile failure in the new consent helper caught a disallowed `Map.get/2`
  guard and was fixed before passing tests.
- Final tests exercise every intent binding, real Citadel governance compilation,
  missing consent-ref denial, expired-consent denial, distinct consent/authority
  enforcement for swaps, receipt-store writes, redaction, rejected consent, actor
  rejection, candidate mismatch, and TTL expiry.

## Verification

- `cd evolution/chassis_evolution_receipts && mix deps.get`: passed.
- `cd evolution/chassis_evolution_receipts && mix format --check-formatted`:
  passed.
- `cd evolution/chassis_evolution_receipts && mix test`: 7 tests, 0 failures.
- `cd evolution/chassis_evolution_receipts && mix deps.tree`: dependency tree is
  `chassis_evolution_contracts -> jason`.
- `cd core/chassis_policy_boundary && mix deps.get`: passed.
- `cd core/chassis_policy_boundary && mix format --check-formatted`: passed.
- `cd core/chassis_policy_boundary && mix test`: 11 tests, 0 failures.
- `cd core/chassis_policy_boundary && mix deps.tree`: includes
  `chassis_boundary`, `chassis_evolution_receipts`, `citadel_governance`, and
  `citadel_authority_contract`.
- Direct smoke:
  `cd core/chassis_policy_boundary && mix run -e '<promote_candidate authorize_intent>'`
  returned `authority:decision:evolution_promote_candidate:925d81a125abf9f3`.
- Grep audit for `operator_consent_ref`, `promote_candidate`,
  `host_daemon:swap`, `authority_intents`, `assert_mutation_authorized`, and
  `authorize_intent` showed the new checks are centralized in the policy and
  receipt packages.
- `mix monorepo.compile --warnings-as-errors`: passed, selected 45 skipped 10
  total 55.
- `mix monorepo.test`: passed, selected 45 skipped 10 total 55.

## Failed / Deferred Checks

- `mix blitz.workspace.impact test --projects chassis_policy_boundary,chassis_evolution_receipts`
  failed before execution with Blitz option parsing:
  `** (Mix) Invalid options: [{"--projects", nil}]`.
- Exact manager-binary smoke
  `./chassis evolution apply --candidate-ref cand:dev:smoke --dry-run --emit-authority-decision --json | jq '.authority_ref'`
  is deferred because post-Phase-20 CLI extension is package-local/disabled; the
  policy-boundary direct smoke used real package logic and returned an
  `authority_ref`.
- `mix ci` failed during workspace format checks on pre-existing out-of-phase
  formatting drift in packages outside Phase 30, including `core/chassis_receipts`,
  `core/chassis_inventory`, `core/chassis_mesh`, `core/chassis_stack`,
  `bootstrap/chassis_bootstrap`, `bootstrap/chassis_doctor`,
  `bootstrap/chassis_installer`, `adapters/chassis_artifact_fs`,
  `adapters/chassis_systemd`, and dependency directories under adapter packages.
  The Phase 30 packages passed their package-local format checks.

## Generated Artifacts

- `_build/` and `deps/` were generated during verification and are ignored/not
  committed.
- `.blitz/test_state_v1/indexes/task_states.ndjson` changed during monorepo/CI
  commands and was restored before commits.
