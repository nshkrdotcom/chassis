defmodule Chassis.Package.HardwareGuard.SmokeTest do
  use ExUnit.Case, async: true

  test "package marker is compiled" do
    assert Chassis.Package.HardwareGuard.package_ref() == "chassis_hardware_guard"
    assert Chassis.Package.HardwareGuard.implemented?()
  end
end
