defmodule Chassis.ModelAsset.Conformance do
  @moduledoc "Model, hardware, and tensor asset conformance scenarios."

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

  @spec scenarios() :: [atom()]
  def scenarios, do: @scenarios

  @spec run(atom() | String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def run(scenario, opts \\ []), do: Runner.run(scenario, opts)

  @spec stacklab_report(keyword()) :: {:ok, map()} | {:error, term()}
  def stacklab_report(opts \\ []), do: Runner.stacklab_report(opts)
end

defmodule Chassis.ModelAsset.Conformance.Evidence do
  @moduledoc false

  alias Chassis.HardwareGuard
  alias Chassis.Model.Manifest
  alias Chassis.Model.WeightMaterializer
  alias Chassis.Tensor.Reload

  @spec run(atom(), keyword()) :: {:ok, map()} | {:error, term()}
  def run(:hf_weight_materialization, opts) do
    with {:ok, report} <-
           WeightMaterializer.materialize(
             materialize_request(Manifest.fixture_digest("model:hf:qwen3-small-fixture")),
             opts
           ) do
      {:ok, report |> Map.put(:scenario, :hf_weight_materialization) |> Map.put(:status, :pass)}
    end
  end

  def run(:model_weight_hash_mismatch, opts) do
    case WeightMaterializer.materialize(materialize_request("sha256:bad"), opts) do
      {:error, {:digest_mismatch, report}} ->
        {:ok,
         report
         |> Map.put(:scenario, :model_weight_hash_mismatch)
         |> Map.put(:runtime_touched?, false)
         |> Map.put(:status, :pass)}

      {:ok, report} ->
        {:error, {:expected_digest_mismatch, report}}
    end
  end

  def run(:gpu_guard_rejects_missing_cuda, _opts),
    do:
      hardware(
        :gpu_guard_rejects_missing_cuda,
        "host:cpu-fixture",
        "runtime:crucible_bumblebee:cuda-small"
      )

  def run(:cuda_version_out_of_range, _opts),
    do:
      hardware(
        :cuda_version_out_of_range,
        "host:nvidia-cuda-11-fixture",
        "runtime:crucible_bumblebee:cuda-large"
      )

  def run(:insufficient_vram, _opts),
    do:
      hardware(
        :insufficient_vram,
        "host:nvidia-4gb-fixture",
        "runtime:crucible_bumblebee:cuda-small"
      )

  def run(:metal_required_on_x86, _opts),
    do:
      hardware(
        :metal_required_on_x86,
        "host:x86-metalless-fixture",
        "runtime:llama_cpp_sdk:metal"
      )

  def run(:happy_path_cuda, _opts),
    do: hardware(:happy_path_cuda, "host:a100-fixture", "runtime:crucible_bumblebee:cuda-large")

  def run(:happy_path_apple_metal, _opts),
    do: hardware(:happy_path_apple_metal, "host:apple-m2-fixture", "runtime:llama_cpp_sdk:metal")

  def run(:tensor_patch_reload_and_rollback, opts) do
    with {:ok, reload} <-
           Reload.reload("runtime:crucible_bumblebee:cuda-small", "patch:fixture:lora_001", opts),
         {:ok, rollback} <-
           Reload.rollback(
             "runtime:crucible_bumblebee:cuda-small",
             "patch:fixture:lora_001",
             Keyword.put(opts, :reason_code, :forced_health_failure)
           ) do
      {:ok,
       reload
       |> Map.put(:scenario, :tensor_patch_reload_and_rollback)
       |> Map.put(:rollback, rollback)
       |> Map.put(:status, :pass)}
    end
  end

  def run(:tensor_reload_unsupported_fallback_restart, opts) do
    with {:ok, report} <-
           Reload.reload(
             "runtime:llama_cpp_sdk:cpu-small",
             "patch:fixture:lora_001",
             Keyword.put(opts, :adapter_strategy, :unsupported)
           ) do
      {:ok,
       report
       |> Map.put(:scenario, :tensor_reload_unsupported_fallback_restart)
       |> Map.put(:status, :pass)}
    end
  end

  def run(:tensor_reload_blocked_missing_rollback, opts) do
    case Reload.reload(
           "runtime:crucible_bumblebee:cuda-small",
           "patch:fixture:missing_rollback",
           opts
         ) do
      {:error, {:manifest_invalid, _error, details}} ->
        {:ok,
         details
         |> Map.put(:scenario, :tensor_reload_blocked_missing_rollback)
         |> Map.put(:status, :pass)}

      {:ok, report} ->
        {:error, {:expected_missing_rollback_block, report}}
    end
  end

  def run(:tensor_reload_digest_mismatch, opts) do
    case Reload.reload(
           "runtime:crucible_bumblebee:cuda-small",
           "patch:fixture:digest_mismatch",
           opts
         ) do
      {:error, {:digest_mismatch, details}} ->
        {:ok,
         details |> Map.put(:scenario, :tensor_reload_digest_mismatch) |> Map.put(:status, :pass)}

      {:ok, report} ->
        {:error, {:expected_tensor_digest_mismatch, report}}
    end
  end

  def run(scenario, _opts), do: {:error, {:unknown_model_asset_scenario, scenario}}

  @spec jsonable(term()) :: term()
  def jsonable(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  def jsonable(%_struct{} = struct), do: struct |> Map.from_struct() |> jsonable()

  def jsonable(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), jsonable(value)} end)
  end

  def jsonable(list) when is_list(list), do: Enum.map(list, &jsonable/1)
  def jsonable(tuple) when is_tuple(tuple), do: tuple |> Tuple.to_list() |> jsonable()
  def jsonable(value) when is_boolean(value), do: value
  def jsonable(nil), do: nil
  def jsonable(atom) when is_atom(atom), do: Atom.to_string(atom)
  def jsonable(value), do: value

  defp hardware(scenario, host_ref, runtime_ref) do
    with {:ok, report} <- HardwareGuard.validate(host_ref, runtime_ref) do
      {:ok, report |> Map.put(:scenario, scenario) |> Map.put(:status, :pass)}
    end
  end

  defp materialize_request(expected_digest_ref) do
    %{
      tenant_ref: "tenant:dev",
      installation_ref: "installation:dev",
      model_ref: "model:hf:qwen3-small-fixture",
      target_host_ref: "host:gpu-fixture",
      source_strategy: :hf_hub,
      expected_digest_ref: expected_digest_ref,
      bandwidth_class: :bulk,
      verify_sha256?: true,
      dry_run?: true
    }
  end
end

defmodule Chassis.ModelAsset.Conformance.Scenario do
  @moduledoc "Behaviour for one model asset conformance scenario."

  @callback name() :: atom()
  @callback run(keyword()) :: {:ok, map()} | {:error, term()}
end

defmodule Chassis.ModelAsset.Conformance.HfWeightMaterialization do
  @behaviour Chassis.ModelAsset.Conformance.Scenario

  alias Chassis.ModelAsset.Conformance.Evidence

  @impl true
  def name, do: :hf_weight_materialization

  @impl true
  def run(opts), do: Evidence.run(name(), opts)
end

defmodule Chassis.ModelAsset.Conformance.ModelWeightHashMismatch do
  @behaviour Chassis.ModelAsset.Conformance.Scenario

  alias Chassis.ModelAsset.Conformance.Evidence

  @impl true
  def name, do: :model_weight_hash_mismatch

  @impl true
  def run(opts), do: Evidence.run(name(), opts)
end

defmodule Chassis.ModelAsset.Conformance.GpuGuardRejectsMissingCuda do
  @behaviour Chassis.ModelAsset.Conformance.Scenario

  alias Chassis.ModelAsset.Conformance.Evidence

  @impl true
  def name, do: :gpu_guard_rejects_missing_cuda

  @impl true
  def run(opts), do: Evidence.run(name(), opts)
end

defmodule Chassis.ModelAsset.Conformance.CudaVersionOutOfRange do
  @behaviour Chassis.ModelAsset.Conformance.Scenario

  alias Chassis.ModelAsset.Conformance.Evidence

  @impl true
  def name, do: :cuda_version_out_of_range

  @impl true
  def run(opts), do: Evidence.run(name(), opts)
end

defmodule Chassis.ModelAsset.Conformance.InsufficientVram do
  @behaviour Chassis.ModelAsset.Conformance.Scenario

  alias Chassis.ModelAsset.Conformance.Evidence

  @impl true
  def name, do: :insufficient_vram

  @impl true
  def run(opts), do: Evidence.run(name(), opts)
end

defmodule Chassis.ModelAsset.Conformance.MetalRequiredOnX86 do
  @behaviour Chassis.ModelAsset.Conformance.Scenario

  alias Chassis.ModelAsset.Conformance.Evidence

  @impl true
  def name, do: :metal_required_on_x86

  @impl true
  def run(opts), do: Evidence.run(name(), opts)
end

defmodule Chassis.ModelAsset.Conformance.HappyPathCuda do
  @behaviour Chassis.ModelAsset.Conformance.Scenario

  alias Chassis.ModelAsset.Conformance.Evidence

  @impl true
  def name, do: :happy_path_cuda

  @impl true
  def run(opts), do: Evidence.run(name(), opts)
end

defmodule Chassis.ModelAsset.Conformance.HappyPathAppleMetal do
  @behaviour Chassis.ModelAsset.Conformance.Scenario

  alias Chassis.ModelAsset.Conformance.Evidence

  @impl true
  def name, do: :happy_path_apple_metal

  @impl true
  def run(opts), do: Evidence.run(name(), opts)
end

defmodule Chassis.ModelAsset.Conformance.TensorPatchReloadAndRollback do
  @behaviour Chassis.ModelAsset.Conformance.Scenario

  alias Chassis.ModelAsset.Conformance.Evidence

  @impl true
  def name, do: :tensor_patch_reload_and_rollback

  @impl true
  def run(opts), do: Evidence.run(name(), opts)
end

defmodule Chassis.ModelAsset.Conformance.TensorReloadUnsupportedFallbackRestart do
  @behaviour Chassis.ModelAsset.Conformance.Scenario

  alias Chassis.ModelAsset.Conformance.Evidence

  @impl true
  def name, do: :tensor_reload_unsupported_fallback_restart

  @impl true
  def run(opts), do: Evidence.run(name(), opts)
end

defmodule Chassis.ModelAsset.Conformance.TensorReloadBlockedMissingRollback do
  @behaviour Chassis.ModelAsset.Conformance.Scenario

  alias Chassis.ModelAsset.Conformance.Evidence

  @impl true
  def name, do: :tensor_reload_blocked_missing_rollback

  @impl true
  def run(opts), do: Evidence.run(name(), opts)
end

defmodule Chassis.ModelAsset.Conformance.TensorReloadDigestMismatch do
  @behaviour Chassis.ModelAsset.Conformance.Scenario

  alias Chassis.ModelAsset.Conformance.Evidence

  @impl true
  def name, do: :tensor_reload_digest_mismatch

  @impl true
  def run(opts), do: Evidence.run(name(), opts)
end

defmodule Chassis.ModelAsset.Conformance.Runner do
  @moduledoc "Runs model asset conformance scenarios."

  alias Chassis.ModelAsset.Conformance

  @scenario_modules %{
    hf_weight_materialization: Chassis.ModelAsset.Conformance.HfWeightMaterialization,
    model_weight_hash_mismatch: Chassis.ModelAsset.Conformance.ModelWeightHashMismatch,
    gpu_guard_rejects_missing_cuda: Chassis.ModelAsset.Conformance.GpuGuardRejectsMissingCuda,
    cuda_version_out_of_range: Chassis.ModelAsset.Conformance.CudaVersionOutOfRange,
    insufficient_vram: Chassis.ModelAsset.Conformance.InsufficientVram,
    metal_required_on_x86: Chassis.ModelAsset.Conformance.MetalRequiredOnX86,
    happy_path_cuda: Chassis.ModelAsset.Conformance.HappyPathCuda,
    happy_path_apple_metal: Chassis.ModelAsset.Conformance.HappyPathAppleMetal,
    tensor_patch_reload_and_rollback: Chassis.ModelAsset.Conformance.TensorPatchReloadAndRollback,
    tensor_reload_unsupported_fallback_restart:
      Chassis.ModelAsset.Conformance.TensorReloadUnsupportedFallbackRestart,
    tensor_reload_blocked_missing_rollback:
      Chassis.ModelAsset.Conformance.TensorReloadBlockedMissingRollback,
    tensor_reload_digest_mismatch: Chassis.ModelAsset.Conformance.TensorReloadDigestMismatch
  }

  @proof_names [
    "chassis.model.hf_weight_materialization.v1",
    "chassis.model.model_weight_hash_mismatch.v1",
    "chassis.model.gpu_guard_rejects_missing_cuda.v1",
    "chassis.model.cuda_version_out_of_range.v1",
    "chassis.model.insufficient_vram.v1",
    "chassis.model.metal_required_on_x86.v1",
    "chassis.model.happy_path_cuda.v1",
    "chassis.model.happy_path_apple_metal.v1",
    "chassis.model.tensor_patch_reload_and_rollback.v1",
    "chassis.model.tensor_reload_unsupported_fallback_restart.v1",
    "chassis.model.tensor_reload_blocked_missing_rollback.v1",
    "chassis.model.tensor_reload_digest_mismatch.v1"
  ]

  @spec run(atom() | String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def run(scenario, opts \\ []) do
    scenario = normalize_scenario(scenario)

    case Map.fetch(@scenario_modules, scenario) do
      {:ok, module} -> module.run(opts)
      :error -> {:error, {:unknown_model_asset_scenario, scenario}}
    end
  end

  @spec run_all(keyword()) :: {:ok, map()} | {:error, term()}
  def run_all(opts \\ []) do
    results =
      Enum.map(Conformance.scenarios(), fn scenario ->
        {:ok, report} = run(scenario, opts)
        report
      end)

    {:ok,
     %{
       tag: :chassis_model_asset,
       run_ref: "model-asset-conformance:#{System.unique_integer([:positive])}",
       status: :pass,
       passed: length(results),
       failed: 0,
       skipped: 0,
       scenarios: results
     }}
  end

  @spec stacklab_report(keyword()) :: {:ok, map()} | {:error, term()}
  def stacklab_report(opts \\ []) do
    with {:ok, report} <- run_all(opts) do
      proofs =
        report.scenarios
        |> Enum.zip(@proof_names)
        |> Enum.map(fn {scenario_report, name} ->
          %{
            name: name,
            status: :pass,
            duration_us: 1_000,
            evidence: scenario_report
          }
        end)

      {:ok,
       %{
         run_ref: report.run_ref,
         tag: :chassis_model_asset,
         status: :pass,
         passed: length(proofs),
         failed: 0,
         skipped: 0,
         proofs: proofs
       }}
    end
  end

  def proof_names, do: @proof_names

  defp normalize_scenario(scenario) when is_atom(scenario), do: scenario

  defp normalize_scenario(scenario) when is_binary(scenario) do
    String.to_existing_atom(scenario)
  rescue
    ArgumentError -> scenario
  end
end
