defmodule Chassis.HardwareGuardTest do
  use ExUnit.Case, async: true

  alias Chassis.HardwareGuard
  alias Chassis.HardwareGuard.CapabilitySnapshot
  alias Chassis.HardwareGuard.RequiredCapabilities
  alias Chassis.HardwareGuard.Receipts.{AdmissionRecord, SnapshotRecord}

  test "gpu_guard_rejects_missing_cuda before placement or runtime side effects" do
    assert {:ok, report} =
             HardwareGuard.validate("host:cpu-fixture", "runtime:crucible_bumblebee:cuda-small",
               trace_id: "trace:phase37:cpu"
             )

    assert report.admission_outcome == :reject
    assert :gpu_vendor_mismatch in report.reason_codes
    assert :container_gpu_runtime_missing in report.reason_codes
    assert :nvidia in report.missing_capabilities
    assert :nvidia_container_runtime in report.missing_capabilities
    assert report.placement_allowed? == false
    assert report.runtime_started? == false
    assert report.host_ref == "host:cpu-fixture"
    assert report.runtime_ref == "runtime:crucible_bumblebee:cuda-small"
    assert report.capability_snapshot_ref =~ "snap:host:cpu-fixture:"
    assert report.capability_digest_summary =~ "sha256:"
    assert report.required_digest_summary =~ "sha256:"

    assert %SnapshotRecord{host_ref: "host:cpu-fixture", trace_id: "trace:phase37:cpu"} =
             report.snapshot_receipt

    assert %AdmissionRecord{
             admission_outcome: :reject,
             reason_codes: reason_codes,
             trace_id: "trace:phase37:cpu"
           } = report.admission_receipt

    assert :gpu_vendor_mismatch in reason_codes
    assert Enum.any?(report.spans, &(&1.name == "chassis.hardware.accelerator.rejected"))
    assert Enum.any?(report.metrics, &(&1.name == "chassis_hardware_guard_rejection_total"))
  end

  test "cuda_version_out_of_range rejects NVIDIA hosts with old drivers" do
    assert {:ok, snapshot} = HardwareGuard.capture_snapshot("host:nvidia-cuda-11-fixture")

    assert {:ok, required} =
             RequiredCapabilities.for_runtime("runtime:crucible_bumblebee:cuda-large")

    assert {:reject, details} = HardwareGuard.validate_accelerator(snapshot, required)
    assert details.reasons == [:cuda_version_out_of_range]
    assert details.missing_capabilities == [:cuda_version_12_0_to_12_6]
  end

  test "insufficient_vram rejects below runtime minimum" do
    assert {:ok, report} =
             HardwareGuard.validate(
               "host:nvidia-4gb-fixture",
               "runtime:crucible_bumblebee:cuda-small"
             )

    assert report.admission_outcome == :reject
    assert :insufficient_vram in report.reason_codes
    assert :vram_bytes in report.missing_capabilities
  end

  test "metal_required_on_x86 rejects missing Apple Silicon and architecture mismatch" do
    assert {:ok, report} =
             HardwareGuard.validate("host:x86-metalless-fixture", "runtime:llama_cpp_sdk:metal")

    assert report.admission_outcome == :reject
    assert :metal_unavailable in report.reason_codes
    assert :cpu_arch_mismatch in report.reason_codes
    assert report.snapshot.gpu.vendor == :none
  end

  test "happy_path_cuda admits A100 fixtures with digest-bound receipts" do
    assert {:ok, report} =
             HardwareGuard.validate("host:a100-fixture", "runtime:crucible_bumblebee:cuda-large")

    assert report.admission_outcome == :admit
    assert report.reason_codes == []
    assert report.missing_capabilities == []
    assert report.placement_allowed?
    assert report.runtime_started? == false
    assert report.snapshot.gpu.model == "NVIDIA A100"
    assert report.snapshot.gpu.vram_bytes == 80 * 1024 * 1024 * 1024
    assert report.required.runtime_ref == "runtime:crucible_bumblebee:cuda-large"
    assert report.admission_receipt.admission_outcome == :admit
    assert Enum.any?(report.spans, &(&1.name == "chassis.hardware.accelerator.validated"))
    refute Enum.any?(report.metrics, &(&1.name == "chassis_hardware_guard_rejection_total"))
  end

  test "happy_path_apple_metal admits Apple Silicon fixtures" do
    assert {:ok, report} =
             HardwareGuard.validate("host:apple-m2-fixture", "runtime:llama_cpp_sdk:metal")

    assert report.admission_outcome == :admit
    assert report.snapshot.cpu.architecture == :aarch64
    assert report.snapshot.gpu.vendor == :apple
    assert report.snapshot.drivers.metal_supported?
  end

  test "capture_snapshot supports local ssh and container fixture adapters" do
    for adapter <- [:local, :ssh, :container] do
      assert {:ok, %CapabilitySnapshot{} = snapshot} =
               HardwareGuard.capture_snapshot("host:a100-fixture", adapter: adapter)

      assert snapshot.host_ref == "host:a100-fixture"
      assert snapshot.source_adapter == adapter
      assert CapabilitySnapshot.digest(snapshot) =~ "sha256:"
    end
  end

  test "unknown hosts and runtimes fail closed" do
    assert {:error, {:unknown_host_fixture, "host:missing"}} =
             HardwareGuard.capture_snapshot("host:missing")

    assert {:error, {:unknown_runtime, "runtime:missing"}} =
             RequiredCapabilities.for_runtime("runtime:missing")
  end
end
