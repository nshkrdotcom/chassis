defmodule Chassis.Tensor.Reload.Adapter do
  @moduledoc "Tensor reload adapter behaviour."
  @callback reload(map(), keyword()) :: {:ok, map()} | {:error, term()}
  @callback rollback(map(), keyword()) :: {:ok, map()} | {:error, term()}
end

for adapter <- [Bumblebee, LlamaCpp, SelfHostedInferenceCore] do
  defmodule Module.concat(Chassis.Tensor.Reload.Adapter, adapter) do
    @moduledoc "Runtime tensor reload adapter."
    def reload(attrs, _opts \\ []), do: {:ok, Map.put(attrs, :strategy_applied, :hot_reload)}

    def rollback(attrs, _opts \\ []),
      do: {:ok, Map.put(attrs, :restored_patch_digest, "sha256:rollback")}
  end
end

defmodule Chassis.Tensor.Reload.PatchManifest do
  @moduledoc "Tensor patch manifest."
  @enforce_keys [:patch_ref, :runtime_ref, :patch_digest, :rollback_digest]
  defstruct [:patch_ref, :runtime_ref, :patch_digest, :rollback_digest]
  def validate!(%__MODULE__{} = manifest), do: manifest
end

defmodule Chassis.Tensor.Reload do
  @moduledoc "Tensor patch reload facade."
  def reload(attrs, opts \\ []), do: Chassis.Tensor.Reload.Adapter.Bumblebee.reload(attrs, opts)

  def rollback(attrs, opts \\ []),
    do: Chassis.Tensor.Reload.Adapter.Bumblebee.rollback(attrs, opts)
end

for record <- [TensorReloadRecord, TensorRollbackRecord] do
  defmodule Module.concat(Chassis.Tensor.Reload.Receipts, record) do
    @moduledoc "Tensor reload receipt."
    defstruct [:receipt_ref, :runtime_ref, :patch_ref, :payload]
  end
end
