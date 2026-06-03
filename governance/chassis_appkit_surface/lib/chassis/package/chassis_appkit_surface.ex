defmodule Chassis.Package.AppkitSurface do
  @moduledoc "Package marker for AppKit spatial surface schemas."

  @spec package_ref() :: String.t()
  def package_ref, do: "chassis_appkit_surface"

  @spec projection_module() :: module()
  def projection_module, do: Chassis.AppKit.Surface.Projection

  @spec error_module() :: module()
  def error_module, do: Chassis.AppKit.Surface.Error
end
