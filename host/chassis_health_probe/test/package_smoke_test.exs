defmodule Chassis.Package.HealthProbe.SmokeTest do
  use ExUnit.Case, async: true

  test "package marker is compiled" do
    assert Chassis.Package.HealthProbe.package_ref() == "chassis_health_probe"
    assert Chassis.Package.HealthProbe.implemented?()
  end
end
