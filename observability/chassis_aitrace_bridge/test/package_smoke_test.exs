defmodule Chassis.Package.AitraceBridge.SmokeTest do
  use ExUnit.Case, async: true

  test "package marker is compiled" do
    assert Chassis.Package.AitraceBridge.package_ref() == "chassis_aitrace_bridge"
    assert Chassis.Package.AitraceBridge.implemented?()
  end
end
