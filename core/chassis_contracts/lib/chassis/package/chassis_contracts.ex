defmodule Chassis.Package.Contracts do
  @moduledoc "Pure DTO schemas and behaviours for NSHKR spatial topology"

  @spec package_ref() :: String.t()
  def package_ref, do: "chassis_contracts"

  @spec implemented?() :: boolean()
  def implemented?, do: true
end
