defmodule Chassis.Package.Receipts do
  @moduledoc "Spatial deployment, health, rollback, model, and evolution receipts"

  @spec package_ref() :: String.t()
  def package_ref, do: "chassis_receipts"

  @spec implemented?() :: boolean()
  def implemented?, do: true
end
