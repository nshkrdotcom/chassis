defmodule Chassis.Adapter.Tofu.Plan do
  @moduledoc "OpenTofu `plan` output DTO."
  @enforce_keys [:plan_ref, :workspace_ref]
  defstruct [:plan_ref, :workspace_ref, changes: []]

  @type change :: %{
          required(:resource_address) => String.t(),
          required(:action) => :create | :update | :delete | :replace | :no_op,
          optional(:before) => map() | nil,
          optional(:after) => map() | nil
        }

  @type t :: %__MODULE__{
          plan_ref: String.t(),
          workspace_ref: String.t(),
          changes: [change()]
        }
end

defmodule Chassis.Adapter.Tofu.Apply do
  @moduledoc "OpenTofu `apply` output DTO."
  @enforce_keys [:apply_ref, :plan_ref, :status]
  defstruct [:apply_ref, :plan_ref, :status, results: []]

  @type t :: %__MODULE__{
          apply_ref: String.t(),
          plan_ref: String.t(),
          status: :ok | :failed | :partial,
          results: [map()]
        }
end

defmodule Chassis.Adapter.Tofu do
  @moduledoc """
  OpenTofu adapter. Phase 8 ships the typed `Plan` and `Apply` DTOs but
  the live `tofu plan` / `tofu apply` execution paths are not in the
  0-43 phase plan; both callbacks return canonical
  `{:error, {:not_implemented, __MODULE__}}` per 0541 §1 row 4.
  """

  @spec plan(map()) :: {:error, {:not_implemented, module()}}
  def plan(_attrs), do: {:error, {:not_implemented, __MODULE__}}

  @spec apply(Chassis.Adapter.Tofu.Plan.t() | map()) :: {:error, {:not_implemented, module()}}
  def apply(_plan), do: {:error, {:not_implemented, __MODULE__}}
end
