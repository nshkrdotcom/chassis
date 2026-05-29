defmodule Chassis.Package.Installer do
  @moduledoc "Target-host installer"

  @spec package_ref() :: String.t()
  def package_ref, do: "chassis_installer"

  @spec implemented?() :: boolean()
  def implemented?, do: true
end
