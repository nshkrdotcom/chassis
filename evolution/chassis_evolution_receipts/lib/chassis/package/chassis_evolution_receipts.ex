defmodule Chassis.Package.EvolutionReceipts do
  @moduledoc "Evolution receipt records"

  @spec package_ref() :: String.t()
  def package_ref, do: "chassis_evolution_receipts"

  @spec implemented?() :: boolean()
  def implemented?, do: true
end
