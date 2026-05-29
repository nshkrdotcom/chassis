defmodule Chassis.Package.Cli do
  @moduledoc "CLI subcommand router"

  @spec package_ref() :: String.t()
  def package_ref, do: "chassis_cli"

  @spec implemented?() :: boolean()
  def implemented?, do: true
end
