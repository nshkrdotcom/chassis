defmodule Chassis.Package.AitraceBridge do
  @moduledoc "AITrace span bridge"

  @spec package_ref() :: String.t()
  def package_ref, do: "chassis_aitrace_bridge"

  @spec implemented?() :: boolean()
  def implemented?, do: true
end
