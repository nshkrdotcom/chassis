defmodule Chassis.Package.Mesh do
  @moduledoc "BEAM TLS mesh and health supervision"

  @spec package_ref() :: String.t()
  def package_ref, do: "chassis_mesh"

  @spec implemented?() :: boolean()
  def implemented?, do: true
end
