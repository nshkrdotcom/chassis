defmodule Chassis.Package.Conformance do
  @moduledoc "Baseline Chassis conformance harness"

  @spec package_ref() :: String.t()
  def package_ref, do: "chassis_conformance"

  @spec implemented?() :: boolean()
  def implemented?, do: true
end
