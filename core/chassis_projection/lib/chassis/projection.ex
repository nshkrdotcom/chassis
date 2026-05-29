defmodule Chassis.Projection.DeploymentStatus do
  @moduledoc "Operator-safe deployment status projection."
  defstruct [:app_ref, :status, :active_profile, :receipt_ref]

  @type t :: %__MODULE__{
          app_ref: String.t() | nil,
          status: atom() | nil,
          active_profile: String.t() | nil,
          receipt_ref: String.t() | nil
        }
end

defmodule Chassis.Projection.AppStatus do
  @moduledoc "Operator-safe app status projection."
  @spec from_registry(map()) :: Chassis.Projection.DeploymentStatus.t()
  def from_registry(entry),
    do: %Chassis.Projection.DeploymentStatus{
      app_ref: Map.get(entry, :app_ref),
      status: Map.get(entry, :status),
      active_profile: Map.get(entry, :active_profile),
      receipt_ref: Map.get(entry, :deployment_receipt_ref)
    }
end
