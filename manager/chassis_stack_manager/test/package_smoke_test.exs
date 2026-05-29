defmodule Chassis.Package.StackManager.SmokeTest do
  use ExUnit.Case, async: true

  test "package marker is compiled" do
    assert Chassis.Package.StackManager.package_ref() == "chassis_stack_manager"
    assert Chassis.Package.StackManager.implemented?()
  end
end
