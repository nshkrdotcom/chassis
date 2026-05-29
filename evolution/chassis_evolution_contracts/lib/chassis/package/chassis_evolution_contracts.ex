defmodule Chassis.Package.EvolutionContracts do
  @moduledoc "Evolution DTOs, states, and behaviours"

  @spec package_ref() :: String.t()
  def package_ref, do: "chassis_evolution_contracts"

  @spec implemented?() :: boolean()
  def implemented?, do: true
end
