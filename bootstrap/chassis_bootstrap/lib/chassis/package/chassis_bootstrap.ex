defmodule Chassis.Package.Bootstrap do
  @moduledoc "Workspace bootstrap and SSH provisioning"

  @spec package_ref() :: String.t()
  def package_ref, do: "chassis_bootstrap"

  @spec implemented?() :: boolean()
  def implemented?, do: true
end
