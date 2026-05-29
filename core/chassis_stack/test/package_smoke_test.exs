defmodule Chassis.Package.Stack.SmokeTest do
  use ExUnit.Case, async: true

  test "package marker is compiled" do
    assert Chassis.Package.Stack.package_ref() == "chassis_stack"
    assert Chassis.Package.Stack.implemented?()
  end
end
