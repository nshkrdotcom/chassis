defmodule Chassis.Package.HardwareGuard do
  @moduledoc "Hardware topology guard"

  @spec package_ref() :: String.t()
  def package_ref, do: "chassis_hardware_guard"

  @spec implemented?() :: boolean()
  def implemented?, do: true
end
