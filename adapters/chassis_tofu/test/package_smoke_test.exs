defmodule Chassis.Package.Tofu.SmokeTest do
  use ExUnit.Case, async: true

  test "package marker is compiled" do
    assert Chassis.Package.Tofu.package_ref() == "chassis_tofu"
    assert Chassis.Package.Tofu.implemented?()
  end
end
