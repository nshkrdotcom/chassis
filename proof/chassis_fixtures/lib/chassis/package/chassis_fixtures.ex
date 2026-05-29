defmodule Chassis.Package.Fixtures do
  @moduledoc "Canonical topology fixtures"

  @spec package_ref() :: String.t()
  def package_ref, do: "chassis_fixtures"

  @spec implemented?() :: boolean()
  def implemented?, do: true
end
