# Phase 43 Report - README And Guide Synchronization

Date: 2026-06-03

## Scope

- Package map scope: no new package activation; README and guide
  synchronization.
- Files changed:
  - `guides/deployment.md`
  - `guides/boundary.md`
  - `guides/operations.md`
  - `guides/evolution.md`
  - `guides/model_assets.md`
- Chassis guide commit:
  `effd12b0ce2ec2450f2352e08c7690e072f30ca0`, pushed.

## Implemented

- Expanded `guides/deployment.md` with Chassis deployment profile, command path,
  receipt expectations, and current root `stack.deploy` status.
- Expanded `guides/boundary.md` with Ring 0 ownership, encoding rules, and
  boundary/model fixture smokes.
- Expanded `guides/operations.md` with core checks, StackLab checks, terminal
  command families, and the current formatter/CLI caveats.
- Expanded `guides/evolution.md` with lifecycle gates, proof command, StackLab
  catalog smoke, and AppKit readback rules.
- Expanded `guides/model_assets.md` with target-host materialization, hardware
  admission, tensor reload, and conformance expectations.
- Confirmed `mix.exs` already includes all `guides/*.md` via `guide_extras =
  Path.wildcard("guides/*.md")`.

## Verification

- Guide content probe:
  `grep -q "Terminal Command Families" README.md`,
  `grep -q "Chassis deploys product releases" guides/deployment.md`,
  `grep -q "Boundary Owners" guides/boundary.md`,
  `grep -q "StackLab Checks" guides/operations.md`,
  `grep -q "Required Gates" guides/evolution.md`, and
  `grep -q "Weight Materialization" guides/model_assets.md`: passed.
- `cd /home/home/p/g/n/chassis && mix docs`: passed.
- `cd /home/home/p/g/n/chassis && mix monorepo.compile --warnings-as-errors`:
  passed, selected 1 skipped 54 total 55.

## Failed / Deferred Checks

- No new Phase 43 guide-specific checks failed.
- Inherited Phase 42 blockers remain:
  - Chassis root `mix format --check-formatted` and `mix ci` fail on broad
    pre-existing formatter drift outside the guide files.
  - Root `mix chassis.stack.deploy ...` still returns the canonical
    not-implemented router payload for `Chassis.CLI.Command.Stack.Deploy`.

## Generated / Unstaged State

- Chassis `.blitz/test_state_v1/indexes/task_states.ndjson` changed during
  verification and remains unstaged generated state.
