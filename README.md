<p align="center">
  <img src="assets/chassis.svg" width="200" height="200" alt="Chassis logo" />
</p>

<p align="center">
  <a href="https://github.com/nshkrdotcom/chassis">
    <img alt="GitHub: chassis" src="https://img.shields.io/badge/GitHub-chassis-0b0f14?logo=github" />
  </a>
  <a href="https://github.com/nshkrdotcom/chassis/blob/main/LICENSE">
    <img alt="License: MIT" src="https://img.shields.io/badge/license-MIT-0b0f14.svg" />
  </a>
</p>

# Chassis

Chassis is the Spatial and Deployment Plane of the NSHKR execution stack. It compiles and materializes stack topologies, inventories host system capabilities (CPU, RAM, GPUs), manages node installations over local processes, systemd, or remote SSH targets, maps release candidate bundles to active topologies, and orchestrates rollbacks, health inspections, and self-upgrades.

This repository is aligned to the modern packet-defined non-umbrella workspace. The package graph and clear ownership boundaries serve as the source of truth, enabling a fully modular stack manager that boots beside the applications it manages.

## Stack Position

Chassis is physically decoupled from standard runtime message flows, allowing bootstrap from the outside:

```text
  Operator / Developer (Bootstrap)
      │
      ├── (Deployment, Lifecycle, Node Topology) ──> Chassis (Spatial Plane)
      │
      ▼ (Application / Governance)
    AppKit (Gateway Plane)
      └─ Mezzanine (Control Plane)
          └─ Citadel (Governance Plane)
              └─ Jido Integration & Execution (Data/Runtime Plane)
                  └─ AITrace (Trace & Proof Plane)
```

## Workspace Design

Chassis is designed first as a standalone stack manager. Its capabilities are structured across dedicated subsystems:

- **core/** packages define abstract topology contracts, deployment state machines, host facts inventory schemas, and serialization or receipt-redaction behaviours.
- **bootstrap/** packages provide safe system preflight check procedures and system installer scripts for quick bootstrapping.
- **manager/** packages implement the primary CLI entrypoint (`chassis doctor`, `chassis status`, `chassis deploy`, etc.) and the engine coordinators.
- **secrets/** packages manage encrypted credential references and lease bindings.
- **adapters/** packages materialize execution plans over raw targets: local commands execution, systemd services supervision, or remote artifact placements.
- **proof/** packages verify the installation integrity using conformed static analysis checks and test fixtures.

## Boundary Invariant

Chassis owns **physical deployment and spatial reality**—the knowledge of exactly what is physically running on which host and under which release version. It is operationally decoupled from Mezzanine (which owns durable workflow and state truth) and Citadel (which compiles authority packets and governs execution policies).

Chassis remains a standalone pre-bootstrap utility: it can create, repair, roll back, and prove the stack without requiring Citadel or Mezzanine to already be running.

## Full-Buildout Implementation Surface

This workspace contains the full Chassis Spatial Plane package map: core,
bootstrap, manager, secrets, adapters, governance, observability, host,
evolution, model, and proof packages. The root escript exposes the deployment,
host, app, key, environment, evolution, hardware, model, tensor, and proof
commands required by the implementation checklist.

The guides in `guides/*.md` document the operational surfaces included in the
workspace docs build.

## Terminal Command Families

The final Chassis proof is exercised through three command families:

```bash
mix chassis.stack.deploy extravaganza \
  --profile profile:ternary-split-3 \
  --env prod

mix chassis.evolution.proof \
  --app extravaganza \
  --profile profile:ternary-split-3 \
  --env prod \
  --fixture fixture:source_level_repair_001 \
  --require-trial \
  --require-citadel-consent \
  --require-health-gated-swap \
  --require-rollback-proof

mix chassis.model.materialize \
  --runtime runtime:crucible_bumblebee:cuda-small \
  --model model:hf:qwen3-small-fixture \
  --target host:gpu-fixture \
  --verify-sha256 \
  --dry-run
```

`guides/deployment.md`, `guides/evolution.md`, `guides/model_assets.md`,
`guides/boundary.md`, and `guides/operations.md` are included in the docs build
and describe the deployment, evolution, model asset, boundary, and operator
surfaces used by those commands.
