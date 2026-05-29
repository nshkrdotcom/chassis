defmodule Chassis.Package.StackManager do
  @moduledoc "Deployment transactions and rollback orchestration"

  @spec package_ref() :: String.t()
  def package_ref, do: "chassis_stack_manager"

  @spec implemented?() :: boolean()
  def implemented?, do: true
end
