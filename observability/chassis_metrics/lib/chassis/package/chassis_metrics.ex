defmodule Chassis.Package.Metrics do
  @moduledoc "Operational metrics and health signal bridge"

  @spec package_ref() :: String.t()
  def package_ref, do: "chassis_metrics"

  @spec implemented?() :: boolean()
  def implemented?, do: true
end
