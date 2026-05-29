defmodule Chassis.Package.Boundary do
  @moduledoc "Ring 0 boundary protocol, envelopes, adapters, and registry"

  @spec package_ref() :: String.t()
  def package_ref, do: "chassis_boundary"

  @spec implemented?() :: boolean()
  def implemented?, do: true
end
