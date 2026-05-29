defmodule Chassis.Package.Projection do
  @moduledoc "Operator-safe read projections"

  @spec package_ref() :: String.t()
  def package_ref, do: "chassis_projection"

  @spec implemented?() :: boolean()
  def implemented?, do: true
end
