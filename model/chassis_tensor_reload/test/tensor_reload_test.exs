defmodule Chassis.Tensor.ReloadTest do
  use ExUnit.Case, async: true

  alias Chassis.Tensor.Reload
  alias Chassis.Tensor.Reload.ManifestError
  alias Chassis.Tensor.Reload.PatchManifest
  alias Chassis.Tensor.Reload.Receipts.{TensorReloadRecord, TensorRollbackRecord}

  test "hot reload happy path emits receipt span and metric" do
    assert {:ok, report} =
             Reload.reload("runtime:crucible_bumblebee:cuda-small", "patch:fixture:lora_001",
               trace_id: "trace:phase40:hot"
             )

    assert report.strategy_applied == :hot_reload
    assert report.outcome == :committed
    assert report.runtime_touched?

    assert %TensorReloadRecord{strategy_applied: :hot_reload, outcome: :committed} =
             report.reload_record

    assert Enum.any?(report.spans, &(&1.name == "chassis.tensor_patch.reload.completed"))
    assert Enum.any?(report.metrics, &(&1.labels.strategy_applied == :hot_reload))
  end

  test "unsupported hot reload falls back to restart runtime" do
    assert {:ok, report} =
             Reload.reload("runtime:llama_cpp_sdk:cpu-small", "patch:fixture:lora_001",
               adapter_strategy: :unsupported
             )

    assert report.strategy_applied == :restart_runtime
    assert report.outcome == :committed
    assert report.reload_record.strategy_applied == :restart_runtime
  end

  test "manifest validation rejects missing rollback before runtime side effects" do
    manifest =
      PatchManifest.fixture("runtime:crucible_bumblebee:cuda-small", "patch:fixture:lora_001")

    bad = %{manifest | rollback_patch_ref: nil}

    assert_raise ManifestError, "rollback_patch_ref is required", fn ->
      PatchManifest.validate!(bad)
    end

    assert {:error, {:manifest_invalid, %ManifestError{}, details}} =
             Reload.reload(
               "runtime:crucible_bumblebee:cuda-small",
               "patch:fixture:missing_rollback"
             )

    assert details.runtime_touched? == false
    assert details.citadel_decision == :deny
  end

  test "rollback restores the rollback patch digest" do
    assert {:ok, report} =
             Reload.rollback("runtime:crucible_bumblebee:cuda-small", "patch:fixture:lora_001",
               reason_code: :forced_probe_failure
             )

    assert report.restored_patch_digest == "sha256:rollback:lora_001"
    assert %TensorRollbackRecord{reason_code: :forced_probe_failure} = report.rollback_record
    assert Enum.any?(report.spans, &(&1.name == "chassis.tensor_patch.rollback.completed"))
  end

  test "digest mismatch refuses without touching runtime" do
    assert {:error, {:digest_mismatch, details}} =
             Reload.reload(
               "runtime:crucible_bumblebee:cuda-small",
               "patch:fixture:digest_mismatch"
             )

    assert details.runtime_touched? == false
    assert details.verify_outcome == :mismatch
    assert Enum.any?(details.spans, &(&1.name == "chassis.model.weight.verify.failed"))
  end
end
