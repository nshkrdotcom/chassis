defmodule Chassis.Package.Boundary.SmokeTest do
  use ExUnit.Case, async: true

  test "package marker is compiled" do
    assert Chassis.Package.Boundary.package_ref() == "chassis_boundary"
    assert Chassis.Package.Boundary.implemented?()
  end
end
