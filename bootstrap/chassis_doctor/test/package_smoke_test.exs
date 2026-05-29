defmodule Chassis.Package.Doctor.SmokeTest do
  use ExUnit.Case, async: true

  test "package marker is compiled" do
    assert Chassis.Package.Doctor.package_ref() == "chassis_doctor"
    assert Chassis.Package.Doctor.implemented?()
  end
end
