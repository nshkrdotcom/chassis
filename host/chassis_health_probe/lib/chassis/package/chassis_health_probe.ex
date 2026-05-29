defmodule Chassis.Package.HealthProbe do
  @moduledoc "Health probe and rollback window"

  @spec package_ref() :: String.t()
  def package_ref, do: "chassis_health_probe"

  @spec implemented?() :: boolean()
  def implemented?, do: true
end
