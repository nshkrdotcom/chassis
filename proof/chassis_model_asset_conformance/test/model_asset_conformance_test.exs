defmodule Chassis.ModelAsset.ConformanceTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Chassis.ModelAsset.Conformance
  alias Chassis.ModelAsset.Conformance.Runner

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

  test "all scenarios are declared in matrix order" do
    assert Conformance.scenarios() == @scenarios
  end

  test "weight materialization scenarios execute real materializer behavior" do
    assert {:ok, materialized} = Conformance.run(:hf_weight_materialization)
    assert materialized.digest_verified == true
    assert materialized.bytes_via_beam_control? == false
    assert materialized.control_channel_bytes == 0
    assert materialized.materialization_record.digest_verified == :ok

    assert {:ok, mismatch} = Conformance.run(:model_weight_hash_mismatch)
    assert mismatch.digest_verified == false
    assert mismatch.verify_record.verify_outcome == :mismatch
    assert mismatch.runtime_touched? == false
  end

  test "hardware guard scenarios execute real admission logic" do
    assert {:ok, missing_cuda} = Conformance.run(:gpu_guard_rejects_missing_cuda)
    assert missing_cuda.admission_outcome == :reject
    assert :gpu_vendor_mismatch in missing_cuda.reason_codes
    assert missing_cuda.placement_allowed? == false

    assert {:ok, cuda_old} = Conformance.run(:cuda_version_out_of_range)
    assert :cuda_version_out_of_range in cuda_old.reason_codes

    assert {:ok, vram} = Conformance.run(:insufficient_vram)
    assert :insufficient_vram in vram.reason_codes

    assert {:ok, metal} = Conformance.run(:metal_required_on_x86)
    assert :metal_unavailable in metal.reason_codes
    assert :cpu_arch_mismatch in metal.reason_codes

    assert {:ok, cuda_ok} = Conformance.run(:happy_path_cuda)
    assert cuda_ok.admission_outcome == :admit

    assert {:ok, apple_ok} = Conformance.run(:happy_path_apple_metal)
    assert apple_ok.admission_outcome == :admit
  end

  test "tensor scenarios execute reload, fallback, rollback, and mismatch behavior" do
    assert {:ok, tensor} = Conformance.run(:tensor_patch_reload_and_rollback)
    assert tensor.strategy_applied == :hot_reload
    assert tensor.rollback.restored_patch_digest == "sha256:rollback:lora_001"

    assert {:ok, fallback} = Conformance.run(:tensor_reload_unsupported_fallback_restart)
    assert fallback.strategy_applied == :restart_runtime

    assert {:ok, blocked} = Conformance.run(:tensor_reload_blocked_missing_rollback)
    assert blocked.runtime_touched? == false
    assert blocked.citadel_decision == :deny

    assert {:ok, mismatch} = Conformance.run(:tensor_reload_digest_mismatch)
    assert mismatch.runtime_touched? == false
    assert mismatch.verify_outcome == :mismatch
  end

  test "runner builds StackLab proof catalog entries with concrete evidence" do
    assert {:ok, report} = Runner.stacklab_report()
    assert report.tag == :chassis_model_asset
    assert report.passed == 12
    assert report.failed == 0
    assert report.skipped == 0
    assert length(report.proofs) == 12
    assert Enum.all?(report.proofs, &(&1.status == :pass))
    assert Enum.all?(report.proofs, &(is_map(&1.evidence) and map_size(&1.evidence) > 0))
  end

  test "model fixture Mix task emits JSON derived from scenario execution" do
    Mix.Task.reenable("chassis.model.fixture")

    output =
      capture_io(fn ->
        Mix.Tasks.Chassis.Model.Fixture.run([
          "--scenario",
          "hf_weight_materialization",
          "--json"
        ])
      end)

    assert {:ok, decoded} = Jason.decode(output)
    assert decoded["scenario"] == "hf_weight_materialization"
    assert decoded["digest_verified"] == true
    assert decoded["bytes_via_beam_control?"] == false
  end
end
