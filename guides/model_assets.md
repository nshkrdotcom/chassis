# Model Asset Guide

Chassis model asset packages handle target-host model weight materialization,
cache indexing, hardware admission, and tensor patch reload/rollback. These
operations are spatial side effects and must remain bounded by authority,
hardware guards, digest checks, and receipt evidence.

## Weight Materialization

Model weights are fetched on the target host. Chassis sends refs and target-side
instructions only; multi-GB artifacts must not traverse BEAM control channels.

```bash
mix chassis.model.materialize --runtime runtime:crucible_bumblebee:cuda-small --model model:hf:qwen3-small-fixture --target host:gpu-fixture --verify-sha256 --dry-run
```

Expected evidence includes `digest_verified: true`,
`bytes_via_beam_control?: false`, and `control_channel_bytes: 0`.

## Hardware Admission

`chassis hardware.validate` evaluates host snapshots against runtime
requirements before placement or runtime startup. Rejection reasons include
missing GPU vendor, insufficient VRAM, CUDA range mismatch, missing Metal, and
container runtime/kernel module gaps.

## Tensor Reload

`chassis tensor.reload` performs hot reload when the runtime supports it and
falls back to runtime restart when required. Every patch manifest needs a
rollback patch ref. Missing rollback and digest mismatch cases must refuse
without touching runtime state.

## Conformance

```bash
mix chassis.model.fixture --scenario hf_weight_materialization --json
cd /home/home/p/g/n/stack_lab
mix stack_lab.run --tag chassis_model_asset | grep PASS
```

The StackLab model asset catalog binds materialization, hash mismatch,
hardware guard, reload, fallback, rollback, and digest mismatch proofs into the
canonical release evidence.
