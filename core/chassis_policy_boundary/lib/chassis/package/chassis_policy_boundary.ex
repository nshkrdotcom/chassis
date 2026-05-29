defmodule Chassis.Package.PolicyBoundary do
  @moduledoc "Citadel authority boundary integration"

  @spec package_ref() :: String.t()
  def package_ref, do: "chassis_policy_boundary"

  @spec implemented?() :: boolean()
  def implemented?, do: true
end
