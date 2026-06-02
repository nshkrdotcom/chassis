defmodule Chassis.Adapter.K8s.Manifest do
  @moduledoc "Typed Kubernetes manifest descriptor."
  @enforce_keys [:api_version, :kind, :metadata]
  defstruct [:api_version, :kind, :metadata, spec: %{}]

  @type t :: %__MODULE__{
          api_version: String.t(),
          kind: String.t(),
          metadata: map(),
          spec: map()
        }
end

defmodule Chassis.Adapter.K8s do
  @moduledoc """
  Kubernetes adapter. Phase 8 ships the `Manifest` DTO and the
  `apply/1` / `delete/1` API surface; live kubectl/API-server execution
  is not in the 0-43 phase plan, so callbacks return canonical
  `{:error, {:not_implemented, __MODULE__}}` per 0541 §1 row 4.
  """

  @spec apply(Chassis.Adapter.K8s.Manifest.t() | map()) ::
          {:error, {:not_implemented, module()}}
  def apply(_manifest), do: {:error, {:not_implemented, __MODULE__}}

  @spec delete(map()) :: {:error, {:not_implemented, module()}}
  def delete(_manifest_ref), do: {:error, {:not_implemented, __MODULE__}}
end
