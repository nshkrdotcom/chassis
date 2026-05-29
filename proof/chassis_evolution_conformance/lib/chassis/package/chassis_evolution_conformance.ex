defmodule Chassis.Package.EvolutionConformance do
  @moduledoc "Evolution conformance scenarios"

  @spec package_ref() :: String.t()
  def package_ref, do: "chassis_evolution_conformance"

  @spec implemented?() :: boolean()
  def implemented?, do: true
end
