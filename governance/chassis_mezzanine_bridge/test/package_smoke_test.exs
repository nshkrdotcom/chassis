defmodule Chassis.Package.MezzanineBridge.SmokeTest do
  use ExUnit.Case, async: true

  test "package marker is compiled" do
    assert Chassis.Package.MezzanineBridge.package_ref() == "chassis_mezzanine_bridge"
    assert Chassis.Package.MezzanineBridge.implemented?()
  end
end
