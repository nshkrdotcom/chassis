defmodule Chassis.AppKit.Surface do
  @moduledoc "Schema package for AppKit spatial gateway."
  @callback get_active_profile(keyword()) :: {:ok, map()} | {:error, term()}
  @callback register_deployed_app(map(), keyword()) :: {:ok, map()} | {:error, term()}
  @callback get_health_status(keyword()) :: {:ok, map()} | {:error, term()}
  @callback trigger_rollback(map(), keyword()) :: {:ok, map()} | {:error, term()}
end

defmodule Chassis.AppKit.Surface.DeploymentProjection do
  @moduledoc "Operator-safe deployment projection."
  defstruct [:app_ref, :active_profile, :status, :receipt_ref]

  @type t :: %__MODULE__{
          app_ref: String.t() | nil,
          active_profile: String.t() | nil,
          status: atom() | nil,
          receipt_ref: String.t() | nil
        }
end

defmodule Chassis.AppKit.EvolutionSurface do
  @moduledoc "Schema package for AppKit evolution readback."
  @callback list_evolution_batches(map(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  @callback get_evolution_status(map(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  @callback record_operator_consent(map(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  @callback get_candidate_diff(map(), map(), keyword()) :: {:ok, map()} | {:error, term()}
end
