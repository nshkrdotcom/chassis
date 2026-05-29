defmodule Chassis.Package.SecretRefs do
  @moduledoc "Secret refs, leases, and materializer behaviour"

  @spec package_ref() :: String.t()
  def package_ref, do: "chassis_secret_refs"

  @spec implemented?() :: boolean()
  def implemented?, do: true
end
