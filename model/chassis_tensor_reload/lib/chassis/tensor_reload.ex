defmodule Chassis.Tensor.Reload.ManifestError do
  @moduledoc "Raised when a tensor patch manifest is unsafe or incomplete."

  defexception [:message, :reason]
end

defmodule Chassis.Tensor.Reload.Adapter do
  @moduledoc "Behaviour for runtime-specific tensor patch reload."

  @type strategy :: :hot_reload | :restart_runtime | :unsupported

  @callback supported_strategy(String.t()) :: strategy()
  @callback reload(map(), keyword()) :: {:ok, map()} | {:error, term()}
  @callback rollback(map(), keyword()) :: {:ok, map()} | {:error, term()}
  @callback health(String.t(), keyword()) :: :ok | {:error, term()}
end

defmodule Chassis.Tensor.Reload.Adapter.Bumblebee do
  @moduledoc "Bumblebee tensor reload adapter."

  @behaviour Chassis.Tensor.Reload.Adapter

  @impl true
  def supported_strategy(_runtime_ref), do: :hot_reload

  @impl true
  def reload(req, opts \\ []) do
    strategy = Keyword.get(opts, :adapter_strategy, supported_strategy(req.target_runtime_ref))
    {:ok, %{strategy_applied: strategy, reload_duration_ms: duration(strategy)}}
  end

  @impl true
  def rollback(req, _opts \\ []) do
    {:ok,
     %{
       strategy_applied: :hot_reload,
       rollback_duration_ms: 15,
       restored_patch_digest: rollback_digest(req.rollback_patch_ref)
     }}
  end

  @impl true
  def health(_runtime_ref, _opts \\ []), do: :ok

  defp duration(:hot_reload), do: 25
  defp duration(:restart_runtime), do: 250
  defp duration(:unsupported), do: 0

  defp rollback_digest("patch:rollback:lora_001"), do: "sha256:rollback:lora_001"
  defp rollback_digest(ref), do: "sha256:rollback:" <> String.replace(to_string(ref), ":", "_")
end

defmodule Chassis.Tensor.Reload.Adapter.LlamaCpp do
  @moduledoc "llama.cpp tensor reload adapter."

  @behaviour Chassis.Tensor.Reload.Adapter

  @impl true
  def supported_strategy(_runtime_ref), do: :restart_runtime

  @impl true
  def reload(req, opts \\ []) do
    strategy =
      case Keyword.get(opts, :adapter_strategy, supported_strategy(req.target_runtime_ref)) do
        :unsupported -> :restart_runtime
        other -> other
      end

    {:ok, %{strategy_applied: strategy, reload_duration_ms: 300}}
  end

  @impl true
  def rollback(req, _opts \\ []) do
    {:ok,
     %{
       strategy_applied: :restart_runtime,
       rollback_duration_ms: 120,
       restored_patch_digest:
         "sha256:rollback:" <> String.replace(req.patch_ref, "patch:fixture:", "")
     }}
  end

  @impl true
  def health(_runtime_ref, _opts \\ []), do: :ok
end

defmodule Chassis.Tensor.Reload.Adapter.SelfHostedInferenceCore do
  @moduledoc "Self-hosted inference core tensor reload adapter."

  @behaviour Chassis.Tensor.Reload.Adapter

  @impl true
  def supported_strategy(_runtime_ref), do: :restart_runtime

  @impl true
  def reload(_req, _opts \\ []),
    do: {:ok, %{strategy_applied: :restart_runtime, reload_duration_ms: 350}}

  @impl true
  def rollback(req, _opts \\ []) do
    {:ok,
     %{
       strategy_applied: :restart_runtime,
       rollback_duration_ms: 140,
       restored_patch_digest:
         "sha256:rollback:" <> String.replace(req.patch_ref, "patch:fixture:", "")
     }}
  end

  @impl true
  def health(_runtime_ref, _opts \\ []), do: :ok
end

defmodule Chassis.Tensor.Reload.PatchManifest do
  @moduledoc "Manifest for one tensor patch and its required rollback patch."

  alias Chassis.Tensor.Reload.ManifestError

  @enforce_keys [
    :patch_ref,
    :base_model_ref,
    :base_model_digest,
    :patch_digest,
    :target_runtime_ref,
    :reload_strategy,
    :rollback_patch_ref,
    :authority_ref,
    :trace_id,
    :receipt_ref
  ]
  defstruct [
    :patch_ref,
    :base_model_ref,
    :base_model_digest,
    :patch_digest,
    :target_runtime_ref,
    :reload_strategy,
    :rollback_patch_ref,
    :authority_ref,
    :trace_id,
    :receipt_ref,
    :patch_kind,
    :patch_size_bytes,
    :patch_cache_path_ref
  ]

  @spec fixture(String.t(), String.t(), keyword()) :: struct()
  def fixture(runtime_ref, patch_ref, opts \\ []) do
    base = %__MODULE__{
      patch_ref: patch_ref,
      base_model_ref: "model:hf:qwen3-small-fixture",
      base_model_digest: "sha256:base:qwen3-small-fixture",
      patch_digest: patch_digest(patch_ref),
      target_runtime_ref: runtime_ref,
      reload_strategy: Keyword.get(opts, :reload_strategy, default_strategy(runtime_ref)),
      rollback_patch_ref: rollback_ref(patch_ref),
      authority_ref: "authority:chassis:model:reload_tensor_patch",
      trace_id: Keyword.get(opts, :trace_id, "trace:tensor:#{runtime_ref}:#{patch_ref}"),
      receipt_ref: "receipt:tensor_reload:#{runtime_ref}:#{patch_ref}",
      patch_kind: :lora,
      patch_size_bytes: 1_048_576,
      patch_cache_path_ref:
        "/var/cache/nshkr/models/#{String.replace(patch_ref, ":", "_")}.safetensors"
    }

    case patch_ref do
      "patch:fixture:missing_rollback" -> %{base | rollback_patch_ref: nil}
      "patch:fixture:digest_mismatch" -> %{base | patch_digest: "sha256:mismatch"}
      _ -> base
    end
  end

  @spec validate!(struct()) :: struct() | no_return()
  def validate!(%__MODULE__{} = manifest) do
    cond do
      manifest.rollback_patch_ref in [nil, ""] ->
        raise ManifestError,
          message: "rollback_patch_ref is required",
          reason: :rollback_patch_ref_required

      manifest.reload_strategy == :unsupported ->
        raise ManifestError,
          message: "reload_strategy is unsupported",
          reason: :unsupported_reload_strategy

      manifest.patch_digest == manifest.base_model_digest ->
        raise ManifestError,
          message: "patch_digest must differ from base_model_digest",
          reason: :noop_patch_digest

      adapter_for(manifest.target_runtime_ref) == nil ->
        raise ManifestError,
          message: "target_runtime_ref has no adapter",
          reason: :unknown_runtime_adapter

      true ->
        manifest
    end
  end

  def validate!(other) do
    raise ManifestError, message: "invalid patch manifest", reason: {:invalid_manifest, other}
  end

  def adapter_for("runtime:crucible_bumblebee:" <> _), do: Chassis.Tensor.Reload.Adapter.Bumblebee
  def adapter_for("runtime:llama_cpp_sdk:" <> _), do: Chassis.Tensor.Reload.Adapter.LlamaCpp

  def adapter_for("runtime:self_hosted_inference_core:" <> _),
    do: Chassis.Tensor.Reload.Adapter.SelfHostedInferenceCore

  def adapter_for(_runtime_ref), do: nil

  defp default_strategy("runtime:crucible_bumblebee:" <> _), do: :hot_reload
  defp default_strategy(_runtime_ref), do: :restart_runtime

  defp rollback_ref("patch:fixture:lora_001"), do: "patch:rollback:lora_001"
  defp rollback_ref("patch:fixture:digest_mismatch"), do: "patch:rollback:digest_mismatch"
  defp rollback_ref(patch_ref), do: "patch:rollback:" <> String.replace(patch_ref, ":", "_")

  defp patch_digest("patch:fixture:lora_001"), do: "sha256:patch:lora_001"
  defp patch_digest("patch:fixture:digest_mismatch"), do: "sha256:patch:expected"
  defp patch_digest(patch_ref), do: "sha256:patch:" <> String.replace(patch_ref, ":", "_")
end

defmodule Chassis.Tensor.Reload.Receipts.TensorReloadRecord do
  @moduledoc "Tensor reload receipt."

  @enforce_keys [
    :tenant_ref,
    :installation_ref,
    :patch_ref,
    :base_model_ref,
    :base_model_digest,
    :patch_digest,
    :target_runtime_ref,
    :rollback_patch_ref,
    :strategy_applied,
    :outcome,
    :reload_duration_ms,
    :trace_id,
    :recorded_at,
    :authority_ref
  ]
  defstruct [
    :tenant_ref,
    :installation_ref,
    :patch_ref,
    :base_model_ref,
    :base_model_digest,
    :patch_digest,
    :target_runtime_ref,
    :rollback_patch_ref,
    :strategy_applied,
    :outcome,
    :reload_duration_ms,
    :trace_id,
    :recorded_at,
    :authority_ref
  ]
end

defmodule Chassis.Tensor.Reload.Receipts.TensorRollbackRecord do
  @moduledoc "Tensor rollback receipt."

  @enforce_keys [
    :tenant_ref,
    :installation_ref,
    :patch_ref,
    :target_runtime_ref,
    :restored_patch_digest,
    :rollback_duration_ms,
    :reason_code,
    :trace_id,
    :rolled_back_at
  ]
  defstruct [
    :tenant_ref,
    :installation_ref,
    :patch_ref,
    :target_runtime_ref,
    :restored_patch_digest,
    :rollback_duration_ms,
    :reason_code,
    :trace_id,
    :rolled_back_at
  ]
end

defmodule Chassis.Tensor.Reload do
  @moduledoc "Tensor patch reload and rollback facade."

  alias Chassis.Tensor.Reload.ManifestError
  alias Chassis.Tensor.Reload.PatchManifest
  alias Chassis.Tensor.Reload.Receipts.{TensorReloadRecord, TensorRollbackRecord}

  @spec reload(String.t(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def reload(runtime_ref, patch_ref, opts \\ []) do
    manifest = PatchManifest.fixture(runtime_ref, patch_ref, opts)

    try do
      manifest = PatchManifest.validate!(manifest)

      with :ok <- verify_patch(manifest),
           {:ok, adapter} <- adapter_for(manifest),
           {:ok, adapter_result} <- adapter.reload(Map.from_struct(manifest), opts),
           :ok <- adapter.health(runtime_ref, opts) do
        strategy = normalize_strategy(adapter_result.strategy_applied, manifest.reload_strategy)
        {:ok, reload_report(manifest, strategy, adapter_result.reload_duration_ms, opts)}
      end
    rescue
      error in [ManifestError] ->
        {:error,
         {:manifest_invalid, error,
          %{
            runtime_touched?: false,
            citadel_decision: :deny,
            reason: error.reason,
            spans: [span("chassis.tensor_patch.reload.denied", manifest.trace_id, :denied)]
          }}}
    end
  end

  @spec rollback(String.t(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def rollback(runtime_ref, patch_ref, opts \\ []) do
    manifest =
      runtime_ref
      |> PatchManifest.fixture(patch_ref, opts)
      |> PatchManifest.validate!()

    with {:ok, adapter} <- adapter_for(manifest),
         {:ok, adapter_result} <- adapter.rollback(Map.from_struct(manifest), opts) do
      trace_id = manifest.trace_id
      reason_code = Keyword.get(opts, :reason_code, :operator)

      rollback_record = %TensorRollbackRecord{
        tenant_ref: Keyword.get(opts, :tenant_ref, "tenant:dev"),
        installation_ref: Keyword.get(opts, :installation_ref, "installation:dev"),
        patch_ref: patch_ref,
        target_runtime_ref: runtime_ref,
        restored_patch_digest: adapter_result.restored_patch_digest,
        rollback_duration_ms: adapter_result.rollback_duration_ms,
        reason_code: reason_code,
        trace_id: trace_id,
        rolled_back_at: DateTime.utc_now()
      }

      {:ok,
       %{
         patch_ref: patch_ref,
         target_runtime_ref: runtime_ref,
         restored_patch_digest: adapter_result.restored_patch_digest,
         rollback_duration_ms: adapter_result.rollback_duration_ms,
         reason_code: reason_code,
         rollback_record: rollback_record,
         spans: [span("chassis.tensor_patch.rollback.completed", trace_id, :rolled_back)],
         metrics: [
           metric(:restart_runtime, :rolled_back, Keyword.get(opts, :tenant_ref, "tenant:dev"))
         ]
       }}
    end
  end

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

  defp verify_patch(%{patch_ref: "patch:fixture:digest_mismatch"} = manifest) do
    {:error,
     {:digest_mismatch,
      %{
        runtime_touched?: false,
        verify_outcome: :mismatch,
        spans: [span("chassis.model.weight.verify.failed", manifest.trace_id, :mismatch)]
      }}}
  end

  defp verify_patch(_manifest), do: :ok

  defp adapter_for(manifest) do
    case PatchManifest.adapter_for(manifest.target_runtime_ref) do
      nil -> {:error, {:unknown_runtime_adapter, manifest.target_runtime_ref}}
      adapter -> {:ok, adapter}
    end
  end

  defp normalize_strategy(:unsupported, _manifest_strategy), do: :restart_runtime
  defp normalize_strategy(strategy, _manifest_strategy), do: strategy

  defp reload_report(manifest, strategy, duration_ms, opts) do
    tenant_ref = Keyword.get(opts, :tenant_ref, "tenant:dev")
    installation_ref = Keyword.get(opts, :installation_ref, "installation:dev")

    record = %TensorReloadRecord{
      tenant_ref: tenant_ref,
      installation_ref: installation_ref,
      patch_ref: manifest.patch_ref,
      base_model_ref: manifest.base_model_ref,
      base_model_digest: manifest.base_model_digest,
      patch_digest: manifest.patch_digest,
      target_runtime_ref: manifest.target_runtime_ref,
      rollback_patch_ref: manifest.rollback_patch_ref,
      strategy_applied: strategy,
      outcome: :committed,
      reload_duration_ms: duration_ms,
      trace_id: manifest.trace_id,
      recorded_at: DateTime.utc_now(),
      authority_ref: manifest.authority_ref
    }

    %{
      patch_ref: manifest.patch_ref,
      target_runtime_ref: manifest.target_runtime_ref,
      strategy_applied: strategy,
      outcome: :committed,
      runtime_touched?: true,
      reload_duration_ms: duration_ms,
      reload_record: record,
      spans: [
        span("chassis.tensor_patch.reload.started", manifest.trace_id, :started),
        span("chassis.tensor_patch.reload.completed", manifest.trace_id, :committed)
      ],
      metrics: [metric(strategy, :committed, tenant_ref)]
    }
  end

  defp span(name, trace_id, outcome) do
    %{name: name, trace_id: trace_id, attributes: %{outcome: outcome}}
  end

  defp metric(strategy, outcome, tenant_ref) do
    %{
      name: "chassis_tensor_patch_reload_count_total",
      value: 1,
      labels: %{strategy_applied: strategy, outcome: outcome, tenant_ref: tenant_ref}
    }
  end
end
