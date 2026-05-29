defmodule Chassis.Package.AppkitSurface do
  @moduledoc "AppKit spatial and evolution surface schemas"

  @spec package_ref() :: String.t()
  def package_ref, do: "chassis_appkit_surface"

  @spec implemented?() :: boolean()
  def implemented?, do: true
end
