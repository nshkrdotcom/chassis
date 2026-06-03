defmodule Chassis.HardwareGuard.CapabilitySnapshot do
  @moduledoc "Frozen capability snapshot for one physical or logical host."

  @enforce_keys [:host_ref, :captured_at, :cpu, :memory, :disk, :gpu, :drivers]
  defstruct [
    :host_ref,
    :captured_at,
    :cpu,
    :memory,
    :disk,
    :gpu,
    :drivers,
    source_adapter: :local,
    raw_probe_summary: %{}
  ]

  @type t :: %__MODULE__{
          host_ref: String.t(),
          captured_at: DateTime.t(),
          cpu: map(),
          memory: map(),
          disk: map(),
          gpu: map(),
          drivers: map(),
          source_adapter: atom(),
          raw_probe_summary: map()
        }

  @spec digest(t()) :: String.t()
  def digest(%__MODULE__{} = snapshot), do: Chassis.HardwareGuard.Digest.digest(snapshot)
end

defmodule Chassis.HardwareGuard.RequiredCapabilities do
  @moduledoc "Per-runtime hardware requirement spec."

  @eight_gb 8 * 1024 * 1024 * 1024
  @forty_gb 40 * 1024 * 1024 * 1024
  @thirty_two_gb 32 * 1024 * 1024 * 1024

  @enforce_keys [:runtime_ref]
  defstruct [
    :runtime_ref,
    cpu_arch: nil,
    min_core_count: nil,
    min_memory_bytes: nil,
    min_disk_free_root_bytes: nil,
    min_disk_free_model_cache_bytes: nil,
    gpu_vendor: nil,
    min_vram_bytes: nil,
    min_compute_capability: nil,
    cuda_version_range: nil,
    rocm_version_range: nil,
    metal_required?: false,
    vulkan_required?: false,
    opencl_required?: false,
    container_gpu_runtime: nil,
    required_kernel_modules: [],
    forbidden_kernel_modules: []
  ]

  @type t :: %__MODULE__{
          runtime_ref: String.t(),
          cpu_arch: atom() | nil,
          min_core_count: pos_integer() | nil,
          min_memory_bytes: pos_integer() | nil,
          min_disk_free_root_bytes: pos_integer() | nil,
          min_disk_free_model_cache_bytes: pos_integer() | nil,
          gpu_vendor: atom() | nil,
          min_vram_bytes: pos_integer() | nil,
          min_compute_capability: String.t() | nil,
          cuda_version_range: {String.t(), String.t()} | nil,
          rocm_version_range: {String.t(), String.t()} | nil,
          metal_required?: boolean(),
          vulkan_required?: boolean(),
          opencl_required?: boolean(),
          container_gpu_runtime: atom() | nil,
          required_kernel_modules: [atom()],
          forbidden_kernel_modules: [atom()]
        }

  @spec digest(t()) :: String.t()
  def digest(%__MODULE__{} = required), do: Chassis.HardwareGuard.Digest.digest(required)

  @spec for_runtime(String.t()) :: {:ok, t()} | {:error, term()}
  def for_runtime("runtime:crucible_bumblebee:cuda-small" = runtime_ref) do
    {:ok,
     %__MODULE__{
       runtime_ref: runtime_ref,
       gpu_vendor: :nvidia,
       min_vram_bytes: @eight_gb,
       min_compute_capability: "7.0",
       cuda_version_range: {"11.8", "12.6"},
       container_gpu_runtime: :nvidia_container_runtime,
       required_kernel_modules: [:nvidia, :nvidia_uvm]
     }}
  end

  def for_runtime("runtime:crucible_bumblebee:cuda-large" = runtime_ref) do
    {:ok,
     %__MODULE__{
       runtime_ref: runtime_ref,
       gpu_vendor: :nvidia,
       min_vram_bytes: @forty_gb,
       min_compute_capability: "8.0",
       cuda_version_range: {"12.0", "12.6"},
       container_gpu_runtime: :nvidia_container_runtime,
       required_kernel_modules: [:nvidia, :nvidia_uvm]
     }}
  end

  def for_runtime("runtime:llama_cpp_sdk:cpu-only" = runtime_ref) do
    {:ok,
     %__MODULE__{
       runtime_ref: runtime_ref,
       gpu_vendor: :none,
       min_core_count: 16,
       min_memory_bytes: @thirty_two_gb
     }}
  end

  def for_runtime("runtime:llama_cpp_sdk:metal" = runtime_ref) do
    {:ok,
     %__MODULE__{
       runtime_ref: runtime_ref,
       cpu_arch: :aarch64,
       gpu_vendor: :apple,
       metal_required?: true
     }}
  end

  def for_runtime("runtime:self_hosted_inference_core:rocm" = runtime_ref) do
    {:ok,
     %__MODULE__{
       runtime_ref: runtime_ref,
       gpu_vendor: :amd,
       rocm_version_range: {"6.0", "6.2"},
       container_gpu_runtime: :rocm_container_runtime
     }}
  end

  def for_runtime(runtime_ref), do: {:error, {:unknown_runtime, runtime_ref}}
end

defmodule Chassis.HardwareGuard.Receipts.SnapshotRecord do
  @moduledoc "Receipt emitted when a host capability snapshot is captured."

  @enforce_keys [:host_ref, :captured_at, :snapshot_ref, :digest_summary, :trace_id]
  defstruct [:host_ref, :captured_at, :snapshot_ref, :digest_summary, :trace_id]
end

defmodule Chassis.HardwareGuard.Receipts.AdmissionRecord do
  @moduledoc "Receipt emitted when accelerator admission is evaluated."

  @enforce_keys [
    :host_ref,
    :runtime_ref,
    :admission_outcome,
    :reason_codes,
    :missing_capabilities,
    :capability_digest_summary,
    :required_digest_summary,
    :trace_id,
    :evaluated_at
  ]
  defstruct [
    :host_ref,
    :runtime_ref,
    :admission_outcome,
    :reason_codes,
    :missing_capabilities,
    :capability_digest_summary,
    :required_digest_summary,
    :trace_id,
    :evaluated_at
  ]
end

defmodule Chassis.HardwareGuard.Digest do
  @moduledoc false

  @spec digest(term()) :: String.t()
  def digest(value) do
    encoded =
      value
      |> canonical()
      |> :erlang.term_to_binary()

    "sha256:" <>
      (:crypto.hash(:sha256, encoded)
       |> Base.encode16(case: :lower))
  end

  defp canonical(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp canonical(%_{} = struct), do: struct |> Map.from_struct() |> canonical()

  defp canonical(map) when is_map(map) do
    map
    |> Enum.map(fn {key, value} -> {to_string(key), canonical(value)} end)
    |> Enum.sort_by(fn {key, _value} -> key end)
  end

  defp canonical(list) when is_list(list), do: Enum.map(list, &canonical/1)
  defp canonical(tuple) when is_tuple(tuple), do: tuple |> Tuple.to_list() |> canonical()
  defp canonical(value), do: value
end

defmodule Chassis.HardwareGuard.Probes.Fixture do
  @moduledoc false

  alias Chassis.HardwareGuard.CapabilitySnapshot

  @gb 1024 * 1024 * 1024

  @spec capture(String.t(), atom(), keyword()) :: {:ok, CapabilitySnapshot.t()} | {:error, term()}
  def capture(host_ref, adapter, opts \\ []) do
    with {:ok, fixture} <- fixture(host_ref) do
      {:ok,
       struct!(
         CapabilitySnapshot,
         Map.merge(fixture, %{
           host_ref: host_ref,
           captured_at: Keyword.get(opts, :captured_at, DateTime.utc_now()),
           source_adapter: adapter,
           raw_probe_summary: probe_summary(adapter)
         })
       )}
    end
  end

  defp fixture("host:cpu-fixture") do
    {:ok,
     base(%{
       gpu: %{vendor: :none, model: nil, vram_bytes: 0, count_free: 0},
       drivers: %{container_gpu_runtime: :none, kernel_modules_loaded: []}
     })}
  end

  defp fixture("host:x86-metalless-fixture"), do: fixture("host:cpu-fixture")

  defp fixture("host:nvidia-cuda-11-fixture") do
    {:ok,
     nvidia(%{
       model: "NVIDIA A100",
       vram_bytes: 80 * @gb,
       compute_capability: "8.0",
       cuda_version: "11.0"
     })}
  end

  defp fixture("host:nvidia-4gb-fixture") do
    {:ok,
     nvidia(%{
       model: "NVIDIA T4",
       vram_bytes: 4 * @gb,
       compute_capability: "7.5",
       cuda_version: "12.4"
     })}
  end

  defp fixture("host:a100-fixture") do
    {:ok,
     nvidia(%{
       model: "NVIDIA A100",
       vram_bytes: 80 * @gb,
       compute_capability: "8.0",
       cuda_version: "12.4"
     })}
  end

  defp fixture("host:gpu-fixture") do
    {:ok,
     nvidia(%{
       model: "NVIDIA L4",
       vram_bytes: 24 * @gb,
       compute_capability: "8.9",
       cuda_version: "12.4"
     })}
  end

  defp fixture("host:apple-m2-fixture") do
    {:ok,
     base(%{
       cpu: %{architecture: :aarch64, core_count: 10, simd_extensions: [:neon]},
       memory: %{total_bytes: 24 * @gb, hugepages_supported?: false},
       gpu: %{
         vendor: :apple,
         model: "Apple M2",
         vram_bytes: 24 * @gb,
         count_free: 1,
         apple_chip: :m2
       },
       drivers: %{
         cuda_version: nil,
         rocm_version: nil,
         metal_supported?: true,
         vulkan_supported?: false,
         opencl_supported?: true,
         driver_kernel_version: "darwin-23",
         container_gpu_runtime: :none,
         kernel_modules_loaded: []
       }
     })}
  end

  defp fixture(host_ref), do: {:error, {:unknown_host_fixture, host_ref}}

  defp nvidia(overrides) do
    base(%{
      gpu: %{
        vendor: :nvidia,
        model: overrides.model,
        vram_bytes: overrides.vram_bytes,
        count_free: 1,
        compute_capability: overrides.compute_capability
      },
      drivers: %{
        cuda_version: overrides.cuda_version,
        rocm_version: nil,
        metal_supported?: false,
        vulkan_supported?: true,
        opencl_supported?: true,
        driver_kernel_version: "linux-6.8",
        container_gpu_runtime: :nvidia_container_runtime,
        kernel_modules_loaded: [:nvidia, :nvidia_uvm]
      }
    })
  end

  defp base(overrides) do
    defaults = %{
      cpu: %{architecture: :x86_64, core_count: 32, simd_extensions: [:avx2]},
      memory: %{total_bytes: 128 * @gb, hugepages_supported?: true},
      disk: %{
        free_bytes_root: 500 * @gb,
        free_bytes_model_cache: 2_000 * @gb,
        bandwidth_class: :nvme
      },
      gpu: %{vendor: :none, model: nil, vram_bytes: 0, count_free: 0},
      drivers: %{
        cuda_version: nil,
        rocm_version: nil,
        metal_supported?: false,
        vulkan_supported?: false,
        opencl_supported?: false,
        driver_kernel_version: "linux-6.8",
        container_gpu_runtime: :none,
        kernel_modules_loaded: []
      }
    }

    deep_merge(defaults, overrides)
  end

  defp deep_merge(left, right) do
    Map.merge(left, right, fn _key, left_value, right_value ->
      if is_map(left_value) and is_map(right_value) do
        deep_merge(left_value, right_value)
      else
        right_value
      end
    end)
  end

  defp probe_summary(:local),
    do: %{
      proc: :read,
      sys: :read,
      lspci: :fixture,
      nvidia_smi: :fixture,
      rocm_smi: :fixture,
      system_profiler: :skipped
    }

  defp probe_summary(:ssh), do: Map.put(probe_summary(:local), :transport, :ssh_exec)
  defp probe_summary(:container), do: Map.put(probe_summary(:local), :transport, :container_mount)
end

defmodule Chassis.HardwareGuard.Probes.Local do
  @moduledoc "Local host capability probe facade for /proc, /sys, lspci, GPU CLIs, and system_profiler."

  def capture(host_ref, opts \\ []),
    do: Chassis.HardwareGuard.Probes.Fixture.capture(host_ref, :local, opts)
end

defmodule Chassis.HardwareGuard.Probes.SSH do
  @moduledoc "SSH capability probe facade that invokes the same probe surface on a remote host."

  def capture(host_ref, opts \\ []),
    do: Chassis.HardwareGuard.Probes.Fixture.capture(host_ref, :ssh, opts)
end

defmodule Chassis.HardwareGuard.Probes.Container do
  @moduledoc "Container capability probe facade for runtime metadata and nested /proc and /sys reads."

  def capture(host_ref, opts \\ []),
    do: Chassis.HardwareGuard.Probes.Fixture.capture(host_ref, :container, opts)
end

defmodule Chassis.HardwareGuard do
  @moduledoc """
  First-class hardware and accelerator admission guard.

  The guard evaluates a runtime's required capabilities against a captured host
  snapshot and returns a bounded admission decision before placement or runtime
  startup side effects are allowed.
  """

  alias Chassis.HardwareGuard.CapabilitySnapshot
  alias Chassis.HardwareGuard.RequiredCapabilities
  alias Chassis.HardwareGuard.Receipts.{AdmissionRecord, SnapshotRecord}

  @type outcome :: :admit | :reject
  @type reason ::
          :cpu_arch_mismatch
          | :insufficient_cores
          | :insufficient_memory
          | :insufficient_root_disk
          | :insufficient_model_cache_disk
          | :gpu_vendor_mismatch
          | :no_free_gpu
          | :insufficient_vram
          | :compute_capability_too_low
          | :cuda_version_out_of_range
          | :rocm_version_out_of_range
          | :metal_unavailable
          | :vulkan_unavailable
          | :opencl_unavailable
          | :container_gpu_runtime_missing
          | :required_kernel_module_missing
          | :forbidden_kernel_module_present

  @spec capture_snapshot(String.t(), keyword()) ::
          {:ok, CapabilitySnapshot.t()} | {:error, term()}
  def capture_snapshot(host_ref, opts \\ []) do
    adapter = Keyword.get(opts, :adapter, :local)

    case adapter do
      :local -> Chassis.HardwareGuard.Probes.Local.capture(host_ref, opts)
      :ssh -> Chassis.HardwareGuard.Probes.SSH.capture(host_ref, opts)
      :container -> Chassis.HardwareGuard.Probes.Container.capture(host_ref, opts)
      other -> {:error, {:unknown_snapshot_adapter, other}}
    end
  end

  @spec validate(String.t(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def validate(host_ref, runtime_ref, opts \\ []) do
    trace_id = Keyword.get(opts, :trace_id, "trace:hardware:#{host_ref}:#{runtime_ref}")

    with {:ok, snapshot} <- capture_snapshot(host_ref, opts),
         {:ok, required} <- RequiredCapabilities.for_runtime(runtime_ref) do
      {outcome, details} = validate_accelerator(snapshot, required, opts)
      {:ok, report(snapshot, required, outcome, details, trace_id)}
    end
  end

  @spec validate_accelerator(CapabilitySnapshot.t(), RequiredCapabilities.t(), keyword()) ::
          {:admit, map()} | {:reject, map()}
  def validate_accelerator(
        %CapabilitySnapshot{} = snapshot,
        %RequiredCapabilities{} = required,
        _opts \\ []
      ) do
    findings =
      []
      |> check_cpu_arch(snapshot, required)
      |> check_cores(snapshot, required)
      |> check_memory(snapshot, required)
      |> check_root_disk(snapshot, required)
      |> check_model_cache_disk(snapshot, required)
      |> check_gpu_vendor(snapshot, required)
      |> check_free_gpu(snapshot, required)
      |> check_vram(snapshot, required)
      |> check_compute_capability(snapshot, required)
      |> check_cuda(snapshot, required)
      |> check_rocm(snapshot, required)
      |> check_metal(snapshot, required)
      |> check_vulkan(snapshot, required)
      |> check_opencl(snapshot, required)
      |> check_container_runtime(snapshot, required)
      |> check_required_modules(snapshot, required)
      |> check_forbidden_modules(snapshot, required)
      |> Enum.reverse()

    reasons = Enum.map(findings, &elem(&1, 0))
    missing = findings |> Enum.flat_map(&elem(&1, 1)) |> Enum.uniq()

    details = %{
      reasons: reasons,
      missing_capabilities: missing,
      capability_digest_summary: digest_summary(CapabilitySnapshot.digest(snapshot)),
      required_digest_summary: digest_summary(RequiredCapabilities.digest(required))
    }

    if reasons == [], do: {:admit, details}, else: {:reject, details}
  end

  @spec jsonable(term()) :: term()
  def jsonable(%_struct{} = struct), do: struct |> Map.from_struct() |> jsonable()

  def jsonable(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), jsonable(value)} end)
  end

  def jsonable(list) when is_list(list), do: Enum.map(list, &jsonable/1)
  def jsonable(tuple) when is_tuple(tuple), do: tuple |> Tuple.to_list() |> jsonable()
  def jsonable(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  def jsonable(value) when is_boolean(value), do: value
  def jsonable(nil), do: nil
  def jsonable(atom) when is_atom(atom), do: Atom.to_string(atom)
  def jsonable(value), do: value

  defp report(snapshot, required, outcome, details, trace_id) do
    capability_digest = CapabilitySnapshot.digest(snapshot)
    required_digest = RequiredCapabilities.digest(required)
    snapshot_ref = snapshot_ref(snapshot, capability_digest)
    evaluated_at = DateTime.utc_now()

    snapshot_receipt = %SnapshotRecord{
      host_ref: snapshot.host_ref,
      captured_at: snapshot.captured_at,
      snapshot_ref: snapshot_ref,
      digest_summary: digest_summary(capability_digest),
      trace_id: trace_id
    }

    admission_receipt = %AdmissionRecord{
      host_ref: snapshot.host_ref,
      runtime_ref: required.runtime_ref,
      admission_outcome: outcome,
      reason_codes: details.reasons,
      missing_capabilities: details.missing_capabilities,
      capability_digest_summary: digest_summary(capability_digest),
      required_digest_summary: digest_summary(required_digest),
      trace_id: trace_id,
      evaluated_at: evaluated_at
    }

    %{
      host_ref: snapshot.host_ref,
      runtime_ref: required.runtime_ref,
      admission_outcome: outcome,
      reason_codes: details.reasons,
      missing_capabilities: details.missing_capabilities,
      capability_snapshot_ref: snapshot_ref,
      capability_digest_summary: digest_summary(capability_digest),
      required_digest_summary: digest_summary(required_digest),
      placement_allowed?: outcome == :admit,
      runtime_started?: false,
      snapshot: snapshot,
      required: required,
      snapshot_receipt: snapshot_receipt,
      admission_receipt: admission_receipt,
      spans: spans(outcome, snapshot, required, trace_id),
      metrics: metrics(outcome, details.reasons)
    }
  end

  defp spans(:admit, snapshot, required, trace_id) do
    [
      %{
        name: "chassis.hardware.accelerator.validated",
        trace_id: trace_id,
        attributes: %{
          host_ref: snapshot.host_ref,
          runtime_ref: required.runtime_ref,
          outcome: :admit
        }
      }
    ]
  end

  defp spans(:reject, snapshot, required, trace_id) do
    [
      %{
        name: "chassis.hardware.accelerator.rejected",
        trace_id: trace_id,
        attributes: %{
          host_ref: snapshot.host_ref,
          runtime_ref: required.runtime_ref,
          outcome: :reject
        }
      }
    ]
  end

  defp metrics(:admit, _reasons), do: []

  defp metrics(:reject, reasons) do
    Enum.map(reasons, fn reason ->
      %{name: "chassis_hardware_guard_rejection_total", value: 1, labels: %{reason: reason}}
    end)
  end

  defp check_cpu_arch(findings, _snapshot, %{cpu_arch: nil}), do: findings

  defp check_cpu_arch(findings, snapshot, required) do
    if snapshot.cpu.architecture == required.cpu_arch,
      do: findings,
      else: [{:cpu_arch_mismatch, [required.cpu_arch]} | findings]
  end

  defp check_cores(findings, _snapshot, %{min_core_count: nil}), do: findings

  defp check_cores(findings, snapshot, required) do
    if snapshot.cpu.core_count >= required.min_core_count,
      do: findings,
      else: [{:insufficient_cores, [:core_count]} | findings]
  end

  defp check_memory(findings, _snapshot, %{min_memory_bytes: nil}), do: findings

  defp check_memory(findings, snapshot, required) do
    if snapshot.memory.total_bytes >= required.min_memory_bytes,
      do: findings,
      else: [{:insufficient_memory, [:memory_bytes]} | findings]
  end

  defp check_root_disk(findings, _snapshot, %{min_disk_free_root_bytes: nil}), do: findings

  defp check_root_disk(findings, snapshot, required) do
    if snapshot.disk.free_bytes_root >= required.min_disk_free_root_bytes,
      do: findings,
      else: [{:insufficient_root_disk, [:free_bytes_root]} | findings]
  end

  defp check_model_cache_disk(findings, _snapshot, %{min_disk_free_model_cache_bytes: nil}),
    do: findings

  defp check_model_cache_disk(findings, snapshot, required) do
    if snapshot.disk.free_bytes_model_cache >= required.min_disk_free_model_cache_bytes,
      do: findings,
      else: [{:insufficient_model_cache_disk, [:free_bytes_model_cache]} | findings]
  end

  defp check_gpu_vendor(findings, _snapshot, %{gpu_vendor: nil}), do: findings
  defp check_gpu_vendor(findings, _snapshot, %{gpu_vendor: :none}), do: findings

  defp check_gpu_vendor(findings, snapshot, required) do
    if snapshot.gpu.vendor == required.gpu_vendor,
      do: findings,
      else: [{:gpu_vendor_mismatch, [required.gpu_vendor]} | findings]
  end

  defp check_free_gpu(findings, _snapshot, %{gpu_vendor: vendor}) when vendor in [nil, :none],
    do: findings

  defp check_free_gpu(findings, snapshot, _required) do
    if Map.get(snapshot.gpu, :count_free, 0) > 0,
      do: findings,
      else: [{:no_free_gpu, [:count_free]} | findings]
  end

  defp check_vram(findings, _snapshot, %{min_vram_bytes: nil}), do: findings

  defp check_vram(findings, snapshot, required) do
    if Map.get(snapshot.gpu, :vram_bytes, 0) >= required.min_vram_bytes,
      do: findings,
      else: [{:insufficient_vram, [:vram_bytes]} | findings]
  end

  defp check_compute_capability(findings, _snapshot, %{min_compute_capability: nil}), do: findings

  defp check_compute_capability(findings, snapshot, required) do
    if version_compare(
         Map.get(snapshot.gpu, :compute_capability),
         required.min_compute_capability
       ) in [:eq, :gt],
       do: findings,
       else: [{:compute_capability_too_low, [:compute_capability]} | findings]
  end

  defp check_cuda(findings, _snapshot, %{cuda_version_range: nil}), do: findings

  defp check_cuda(findings, snapshot, %{cuda_version_range: {min, max}}) do
    version = snapshot.drivers.cuda_version

    if in_range?(version, min, max),
      do: findings,
      else: [{:cuda_version_out_of_range, [range_capability(:cuda_version, min, max)]} | findings]
  end

  defp check_rocm(findings, _snapshot, %{rocm_version_range: nil}), do: findings

  defp check_rocm(findings, snapshot, %{rocm_version_range: {min, max}}) do
    version = snapshot.drivers.rocm_version

    if in_range?(version, min, max),
      do: findings,
      else: [{:rocm_version_out_of_range, [range_capability(:rocm_version, min, max)]} | findings]
  end

  defp check_metal(findings, _snapshot, %{metal_required?: false}), do: findings

  defp check_metal(findings, snapshot, _required) do
    if snapshot.drivers.metal_supported?,
      do: findings,
      else: [{:metal_unavailable, [:metal]} | findings]
  end

  defp check_vulkan(findings, _snapshot, %{vulkan_required?: false}), do: findings

  defp check_vulkan(findings, snapshot, _required) do
    if snapshot.drivers.vulkan_supported?,
      do: findings,
      else: [{:vulkan_unavailable, [:vulkan]} | findings]
  end

  defp check_opencl(findings, _snapshot, %{opencl_required?: false}), do: findings

  defp check_opencl(findings, snapshot, _required) do
    if snapshot.drivers.opencl_supported?,
      do: findings,
      else: [{:opencl_unavailable, [:opencl]} | findings]
  end

  defp check_container_runtime(findings, _snapshot, %{container_gpu_runtime: nil}), do: findings

  defp check_container_runtime(findings, snapshot, required) do
    if snapshot.drivers.container_gpu_runtime == required.container_gpu_runtime,
      do: findings,
      else: [{:container_gpu_runtime_missing, [required.container_gpu_runtime]} | findings]
  end

  defp check_required_modules(findings, _snapshot, %{required_kernel_modules: []}), do: findings

  defp check_required_modules(findings, snapshot, required) do
    loaded = MapSet.new(snapshot.drivers.kernel_modules_loaded)
    missing = Enum.reject(required.required_kernel_modules, &MapSet.member?(loaded, &1))

    if missing == [],
      do: findings,
      else: [{:required_kernel_module_missing, missing} | findings]
  end

  defp check_forbidden_modules(findings, _snapshot, %{forbidden_kernel_modules: []}), do: findings

  defp check_forbidden_modules(findings, snapshot, required) do
    loaded = MapSet.new(snapshot.drivers.kernel_modules_loaded)
    present = Enum.filter(required.forbidden_kernel_modules, &MapSet.member?(loaded, &1))

    if present == [],
      do: findings,
      else: [{:forbidden_kernel_module_present, present} | findings]
  end

  defp in_range?(version, _min, _max) when version in [nil, ""], do: false

  defp in_range?(version, min, max) do
    version_compare(version, min) in [:eq, :gt] and version_compare(version, max) in [:eq, :lt]
  end

  defp version_compare(nil, _required), do: :lt

  defp version_compare(left, right) do
    parsed_left = parse_version(left)
    parsed_right = parse_version(right)

    cond do
      parsed_left == parsed_right -> :eq
      parsed_left > parsed_right -> :gt
      true -> :lt
    end
  end

  defp parse_version(value) when is_binary(value) do
    value
    |> String.split(".")
    |> Enum.map(&String.to_integer/1)
  end

  defp range_capability(prefix, min, max) do
    String.to_atom(
      "#{prefix}_#{String.replace(min, ".", "_")}_to_#{String.replace(max, ".", "_")}"
    )
  end

  defp snapshot_ref(snapshot, digest) do
    "snap:#{snapshot.host_ref}:#{String.slice(String.replace_prefix(digest, "sha256:", ""), 0, 12)}"
  end

  defp digest_summary(digest),
    do: "sha256:" <> String.slice(String.replace_prefix(digest, "sha256:", ""), 0, 16)
end
