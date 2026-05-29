# Evolution Guide

This guide is part of the Chassis full-buildout documentation set. Chassis is
the Spatial Plane for NSHKR and materializes governed intent only after Ring 0
boundary validation, tenant and residency checks, Citadel authority, bounded
AITrace evidence, and operational metrics.

The supported local smoke commands are:

```bash
mix chassis.stack.deploy extravaganza --profile profile:monolith --env dev
mix chassis.evolution.proof --app extravaganza --profile profile:ternary-split-3 --env prod --fixture fixture:source_level_repair_001 --require-trial --require-citadel-consent --require-health-gated-swap --require-rollback-proof
mix chassis.model.materialize --runtime runtime:crucible_bumblebee:cuda-small --model model:hf:qwen3-small-fixture --target host:gpu-fixture --verify-sha256 --dry-run
```
