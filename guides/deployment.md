# Deployment Guide

Chassis deploys product releases as the NSHKR Spatial Plane. It receives a
governed deployment intent, resolves the requested topology profile, validates
tenant and residency rules, materializes release placement, records receipts,
and publishes readback for AppKit and Mezzanine.

## Profiles

- `profile:monolith` keeps the product on one local/dev node.
- `profile:decoupled-cockpit-2` separates cockpit/operator services from the
  runtime lane.
- `profile:ternary-split-3` separates cockpit, runtime, and data services.
- `profile:maximal-decoupled` expands every placement into independent nodes.

Each profile is resolved for `:dev` or `:prod` and then composed with host
inventory. In prod, Chassis must have host discovery, provisioner, mesh, and
authority context before the deploy is considered real.

## Command Path

The terminal deployment command is:

```bash
mix chassis.stack.deploy extravaganza --profile profile:ternary-split-3 --env prod
```

At the time of this guide, the root Mix task still reaches the root CLI
not-implemented route for `Chassis.CLI.Command.Stack.Deploy`; this is recorded
in `docs/implementation_notes/phase_42_report.md`. The command must eventually
execute real stack manager logic, not a static CLI response.

## Receipt Expectations

A successful deployment emits:

- a deployment receipt ref
- app ref and active profile
- node mesh membership
- Citadel authority ref
- idempotency/fence ref
- bounded AITrace and metrics evidence

Do not replace valid production, receipt, or snapshot pointers with failed or
incomplete artifacts. Rollback pointers are production state.
