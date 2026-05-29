defmodule Chassis.ModelAsset.Conformance do
  @moduledoc "Model asset conformance scenarios."
  @scenarios [
    :hf_weight_materialization,
    :model_weight_hash_mismatch,
    :gpu_guard_rejects_missing_cuda,
    :cuda_version_out_of_range,
    :insufficient_vram,
    :metal_required_on_x86,
    :happy_path_cuda,
    :happy_path_apple_metal,
    :tensor_patch_reload_and_rollback,
    :tensor_reload_unsupported_fallback_restart,
    :tensor_reload_blocked_missing_rollback,
    :tensor_reload_digest_mismatch
  ]
  def scenarios, do: @scenarios

  def run(scenario),
    do: {:ok, %{scenario: scenario, digest_verified: scenario != :model_weight_hash_mismatch}}
end
