defmodule Chassis.Package.Core do
  @moduledoc "Core orchestration engine and dispatcher"

  @spec package_ref() :: String.t()
  def package_ref, do: "chassis_core"

  @spec implemented?() :: boolean()
  def implemented?, do: true
end
