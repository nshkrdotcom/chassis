# Evolution Guide

Chassis Evolution converts a verified failure batch into a candidate patch,
trial run, score, operator consent decision, health-gated swap, and rollback
proof. Chassis owns the substrate side of that lifecycle; Mezzanine owns
workflow truth, Citadel owns authority and consent, AppKit owns product-safe
readback, and StackLab owns proof certification.

## Required Gates

- Failure batches carry refs and bounded evidence, not raw private bodies.
- Coding-agent runs are budgeted and authority-gated.
- Trial runtimes are isolated and may not mount forbidden production state.
- Candidate scoring blocks promotion on regression.
- Promotion requires Citadel authority and a distinct operator consent ref.
- Host swaps commit only after health probes.
- Rollback proof must exist before production pointer replacement.

## Proof Command

```bash
mix chassis.evolution.proof --app extravaganza --profile profile:ternary-split-3 --env prod --fixture fixture:source_level_repair_001 --require-trial --require-citadel-consent --require-health-gated-swap --require-rollback-proof
```

The proof command exercises the Chassis evolution conformance harness. StackLab
also exposes the external catalog:

```bash
cd /home/home/p/g/n/stack_lab
mix stack_lab.run --tag chassis_evolution | grep PASS
```

## Readback

Product and operator surfaces read through `AppKit.EvolutionSurface`. Product
DTOs may carry refs, bounded summaries, score summaries, status, and receipt
refs. They must not carry raw diffs by default.
