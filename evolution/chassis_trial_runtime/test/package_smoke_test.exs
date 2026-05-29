defmodule Chassis.Package.TrialRuntime.SmokeTest do
  use ExUnit.Case, async: true

  test "package marker is compiled" do
    assert Chassis.Package.TrialRuntime.package_ref() == "chassis_trial_runtime"
    assert Chassis.Package.TrialRuntime.implemented?()
  end
end
