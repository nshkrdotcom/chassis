defmodule Chassis.Package.Stack do
  @moduledoc "Profile resolution, placement, and composition"

  @spec package_ref() :: String.t()
  def package_ref, do: "chassis_stack"

  @spec implemented?() :: boolean()
  def implemented?, do: true
end
