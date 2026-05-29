defmodule Chassis.Mezzanine.Bridge do
  @moduledoc "Mezzanine bridge facade."
end

for name <- [
      MaterializeDeployment,
      RollbackDeployment,
      InspectHost,
      ValidateTopology,
      DrainHost,
      ProvisionHost
    ] do
  defmodule Module.concat(Chassis.Mezzanine.Bridge, name) do
    @moduledoc "Mezzanine bridge operation."
    @spec call(map(), keyword()) :: {:ok, map()} | {:error, term()}
    def call(payload, opts \\ []),
      do:
        Chassis.Mezzanine.Bridge.Outbox.publish(%{
          operation: inspect(__MODULE__),
          payload: payload,
          opts: opts
        })
  end
end

defmodule Chassis.Mezzanine.Bridge.Outbox do
  @moduledoc "Outbox publisher."
  @spec publish(map()) :: {:ok, map()}
  def publish(event), do: {:ok, Map.put(event, :outbox_ref, "outbox:chassis:smoke")}
end

defmodule Chassis.Mezzanine.Bridge.ProjectionPublisher do
  @moduledoc "Projection publisher."
  @spec publish(map()) :: {:ok, map()}
  def publish(projection), do: {:ok, Map.put(projection, :published?, true)}
end
