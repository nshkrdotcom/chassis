# Boundary Guide

Chassis crosses stack boundaries only through bounded Ring 0 envelopes. A
boundary request carries tenant context, authority refs, idempotency keys,
trace ids, and ref-shaped payloads. It must not carry raw credentials, raw
provider payloads, BEAM process identifiers, or mutable runtime state as
authority.

## Boundary Owners

- AppKit owns product/operator-safe DTOs.
- Mezzanine owns durable workflow truth and read projections.
- Citadel owns authority and explicit operator consent policy.
- Chassis owns substrate materialization and receipts.
- GroundPlane owns primitive codecs, fences, checkpoints, and ref contracts.
- AITrace owns bounded trace/evidence export.

## Encoding Rules

Use `GroundPlane.Boundary.Codec.encode!/1` for stack-significant envelopes and
hashes. Chassis payloads should carry refs, digests, summary counts, and
receipt ids. If a field would be a raw secret, raw prompt, raw diff, raw model
weight, or raw private transcript, it belongs behind a lower-read lease or in
an owning lower plane, not in a default Chassis envelope.

## Boundary Smokes

The proof packages exercise these invariants:

```bash
mix chassis.evolution.proof --app extravaganza --profile profile:ternary-split-3 --env prod --fixture fixture:source_level_repair_001 --require-trial --require-citadel-consent --require-health-gated-swap --require-rollback-proof
mix chassis.model.fixture --scenario hf_weight_materialization --json
```

The model fixture must report `bytes_via_beam_control?: false` and
`control_channel_bytes: 0`.
