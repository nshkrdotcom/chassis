defmodule Chassis.Package.Local do
  @moduledoc "Local process adapter"

  @spec package_ref() :: String.t()
  def package_ref, do: "chassis_local"

  @spec implemented?() :: boolean()
  def implemented?, do: true
end
