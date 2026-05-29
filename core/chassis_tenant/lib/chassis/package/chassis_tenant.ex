defmodule Chassis.Package.Tenant do
  @moduledoc "Tenant isolation, residency, and quota guards"

  @spec package_ref() :: String.t()
  def package_ref, do: "chassis_tenant"

  @spec implemented?() :: boolean()
  def implemented?, do: true
end
