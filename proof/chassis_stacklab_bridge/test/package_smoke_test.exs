defmodule Chassis.Package.StacklabBridge.SmokeTest do
  use ExUnit.Case, async: true

  test "package marker is compiled" do
    assert Chassis.Package.StacklabBridge.package_ref() == "chassis_stacklab_bridge"
    assert Chassis.Package.StacklabBridge.implemented?()
  end
end
