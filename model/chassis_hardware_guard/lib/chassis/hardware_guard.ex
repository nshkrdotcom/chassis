defmodule Chassis.HardwareGuard.CapabilitySnapshot do
  @moduledoc "Host hardware capability snapshot."
  defstruct [
    :host_ref,
    cpu_cores: 0,
    gpu_count: 0,
    cuda_version: nil,
    vram_gb: 0,
    metal?: false,
    captured_at: nil
  ]
end

defmodule Chassis.HardwareGuard.RequiredCapabilities do
  @moduledoc "Runtime hardware requirements."
  defstruct [:runtime_ref, min_gpu_count: 0, min_vram_gb: 0, cuda: nil, metal?: false]
end

defmodule Chassis.HardwareGuard do
  @moduledoc "Accelerator and driver admission gate."
  def snapshot(host_ref),
    do: %Chassis.HardwareGuard.CapabilitySnapshot{
      host_ref: host_ref,
      cpu_cores: 8,
      gpu_count: if(String.contains?(host_ref, "gpu"), do: 1, else: 0),
      vram_gb: if(String.contains?(host_ref, "gpu"), do: 24, else: 0),
      captured_at: DateTime.utc_now()
    }

  def validate(host_ref, runtime_ref) do
    snap = snapshot(host_ref)

    outcome =
      if String.contains?(runtime_ref, "cuda") and snap.gpu_count == 0, do: :reject, else: :admit

    {:ok, %{host_ref: host_ref, runtime_ref: runtime_ref, admission_outcome: outcome}}
  end
end

defmodule Chassis.HardwareGuard.Receipts.SnapshotRecord do
  @moduledoc "Hardware snapshot receipt."
  defstruct [:host_ref, :snapshot_ref]
end

defmodule Chassis.HardwareGuard.Receipts.AdmissionRecord do
  @moduledoc "Hardware admission receipt."
  defstruct [:host_ref, :runtime_ref, :admission_outcome]
end
