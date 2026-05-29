defmodule Chassis.Package.Environments do
  @moduledoc "Compile-time embedded provisioning profiles"

  @spec package_ref() :: String.t()
  def package_ref, do: "chassis_environments"

  @spec implemented?() :: boolean()
  def implemented?, do: true
end
