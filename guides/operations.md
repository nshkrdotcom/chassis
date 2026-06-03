# Operations Guide

This guide lists the operator-facing Chassis checks that should be run before
claiming a local or release proof.

## Core Checks

```bash
mix docs
mix monorepo.compile --warnings-as-errors
mix chassis.evolution.proof --app extravaganza --profile profile:ternary-split-3 --env prod --fixture fixture:source_level_repair_001 --require-trial --require-citadel-consent --require-health-gated-swap --require-rollback-proof
mix chassis.model.fixture --scenario hf_weight_materialization --json
```

`mix ci` is the intended full gate. Phase 42 records that it currently fails
at workspace formatting because earlier packages and package-local dependency
trees are included in formatter checks. Do not fix that by formatting vendored
dependencies inside a docs phase.

## StackLab Checks

```bash
cd /home/home/p/g/n/stack_lab
mix stack_lab.run --tag chassis_evolution | grep PASS
mix stack_lab.run --tag chassis_model_asset | grep PASS
```

These proof catalogs certify Chassis evolution and model asset behavior from
outside the Chassis repo.

## Terminal Command Families

```bash
mix chassis.stack.deploy extravaganza --profile profile:ternary-split-3 --env prod
mix chassis.evolution.proof --app extravaganza --profile profile:ternary-split-3 --env prod --fixture fixture:source_level_repair_001 --require-trial --require-citadel-consent --require-health-gated-swap --require-rollback-proof
mix chassis.model.materialize --runtime runtime:crucible_bumblebee:cuda-small --model model:hf:qwen3-small-fixture --target host:gpu-fixture --verify-sha256 --dry-run
```

If any terminal command returns a `not_implemented` router payload, the CLI path
is not done even if a lower package has tests.
