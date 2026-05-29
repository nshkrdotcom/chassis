defmodule Chassis.Package.MezzanineBridge do
  @moduledoc "Mezzanine workflow bridge"

  @spec package_ref() :: String.t()
  def package_ref, do: "chassis_mezzanine_bridge"

  @spec implemented?() :: boolean()
  def implemented?, do: true
end
