defmodule Chassis.Package.Doctor do
  @moduledoc "Node, host, and mesh diagnostics"

  @spec package_ref() :: String.t()
  def package_ref, do: "chassis_doctor"

  @spec implemented?() :: boolean()
  def implemented?, do: true
end
