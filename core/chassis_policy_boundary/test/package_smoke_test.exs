defmodule Chassis.Package.PolicyBoundary.SmokeTest do
  use ExUnit.Case, async: true

  test "package marker is compiled" do
    assert Chassis.Package.PolicyBoundary.package_ref() == "chassis_policy_boundary"
    assert Chassis.Package.PolicyBoundary.implemented?()
  end
end
