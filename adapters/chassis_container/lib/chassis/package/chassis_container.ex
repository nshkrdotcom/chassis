defmodule Chassis.Package.Container do
  @moduledoc "Docker and Podman container adapter"

  @spec package_ref() :: String.t()
  def package_ref, do: "chassis_container"

  @spec implemented?() :: boolean()
  def implemented?, do: true
end
