defmodule Chassis.Package.StacklabBridge do
  @moduledoc "StackLab proof bridge"

  @spec package_ref() :: String.t()
  def package_ref, do: "chassis_stacklab_bridge"

  @spec implemented?() :: boolean()
  def implemented?, do: true
end
