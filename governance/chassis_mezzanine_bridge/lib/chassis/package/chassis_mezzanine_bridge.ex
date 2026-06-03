defmodule Chassis.Package.ChassisMezzanineBridge do
  @moduledoc "Package marker for the Chassis-side Mezzanine bridge."

  @spec bridge() :: module()
  def bridge, do: Chassis.Mezzanine.Bridge

  @spec operations() :: [atom()]
  def operations, do: bridge().operations()
end
