defmodule Chassis.Package.TrialSupervisor.SmokeTest do
  use ExUnit.Case, async: true

  test "package marker is compiled" do
    assert Chassis.Package.TrialSupervisor.package_ref() == "chassis_trial_supervisor"
    assert Chassis.Package.TrialSupervisor.implemented?()
  end
end
