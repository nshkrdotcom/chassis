defmodule Chassis.Package.TrialRuntime do
  @moduledoc "Trial runtime providers"

  @spec package_ref() :: String.t()
  def package_ref, do: "chassis_trial_runtime"

  @spec implemented?() :: boolean()
  def implemented?, do: true
end
