defmodule Chassis.Package.Releases do
  @moduledoc "Release bundles, app registry, and approved mounts"

  @spec package_ref() :: String.t()
  def package_ref, do: "chassis_releases"

  @spec implemented?() :: boolean()
  def implemented?, do: true
end
