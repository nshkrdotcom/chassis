defmodule Chassis.Package.ChassisProjection do
  @moduledoc "Package marker for the Chassis projection package."

  @spec reducer() :: module()
  def reducer, do: Chassis.Projection.ChassisDeploymentProjection

  @spec store() :: module()
  def store, do: Chassis.Projection.Store.Memory
end
