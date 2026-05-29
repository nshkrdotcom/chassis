defmodule Chassis.Package.SwapSupervisor do
  @moduledoc "State-preserving swap supervisor"

  @spec package_ref() :: String.t()
  def package_ref, do: "chassis_swap_supervisor"

  @spec implemented?() :: boolean()
  def implemented?, do: true
end
