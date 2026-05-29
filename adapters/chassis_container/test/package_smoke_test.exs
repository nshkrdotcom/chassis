defmodule Chassis.Package.Container.SmokeTest do
  use ExUnit.Case, async: true

  test "package marker is compiled" do
    assert Chassis.Package.Container.package_ref() == "chassis_container"
    assert Chassis.Package.Container.implemented?()
  end
end
