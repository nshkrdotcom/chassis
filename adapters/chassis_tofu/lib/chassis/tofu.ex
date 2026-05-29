defmodule Chassis.Adapter.Tofu.Plan do
  @moduledoc "OpenTofu plan DTO."
  defstruct [:plan_ref, :workspace_ref, :changes]

  @type t :: %__MODULE__{
          plan_ref: String.t() | nil,
          workspace_ref: String.t() | nil,
          changes: list() | nil
        }
end

defmodule Chassis.Adapter.Tofu.Apply do
  @moduledoc "OpenTofu apply DTO."
  defstruct [:apply_ref, :plan_ref, :status]

  @type t :: %__MODULE__{
          apply_ref: String.t() | nil,
          plan_ref: String.t() | nil,
          status: atom() | nil
        }
end

defmodule Chassis.Adapter.Tofu do
  @moduledoc "OpenTofu adapter stub."
  def plan(_attrs), do: {:error, :not_implemented}
  def apply(_plan), do: {:error, :not_implemented}
end
