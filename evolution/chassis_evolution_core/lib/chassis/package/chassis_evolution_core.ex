defmodule Chassis.Package.EvolutionCore do
  @moduledoc "Evolution lifecycle GenServer"

  @spec package_ref() :: String.t()
  def package_ref, do: "chassis_evolution_core"

  @spec implemented?() :: boolean()
  def implemented?, do: true
end
