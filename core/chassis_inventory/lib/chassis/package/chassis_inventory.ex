defmodule Chassis.Package.Inventory do
  @moduledoc "Host, capacity, GPU, and discovery inventory"

  @spec package_ref() :: String.t()
  def package_ref, do: "chassis_inventory"

  @spec implemented?() :: boolean()
  def implemented?, do: true
end
