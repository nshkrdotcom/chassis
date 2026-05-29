defmodule Chassis.Package.Projection.SmokeTest do
  use ExUnit.Case, async: true

  test "package marker is compiled" do
    assert Chassis.Package.Projection.package_ref() == "chassis_projection"
    assert Chassis.Package.Projection.implemented?()
  end
end
