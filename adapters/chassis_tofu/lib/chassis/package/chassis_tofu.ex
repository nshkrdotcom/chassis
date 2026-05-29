defmodule Chassis.Package.Tofu do
  @moduledoc "OpenTofu plan/apply adapter"

  @spec package_ref() :: String.t()
  def package_ref, do: "chassis_tofu"

  @spec implemented?() :: boolean()
  def implemented?, do: true
end
