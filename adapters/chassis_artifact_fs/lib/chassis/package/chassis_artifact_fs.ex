defmodule Chassis.Package.ArtifactFs do
  @moduledoc "Local artifact cache"

  @spec package_ref() :: String.t()
  def package_ref, do: "chassis_artifact_fs"

  @spec implemented?() :: boolean()
  def implemented?, do: true
end
