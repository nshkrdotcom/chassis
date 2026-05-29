defmodule Chassis.Package.TrialSupervisor do
  @moduledoc "Trial worker build/start supervisor"

  @spec package_ref() :: String.t()
  def package_ref, do: "chassis_trial_supervisor"

  @spec implemented?() :: boolean()
  def implemented?, do: true
end
