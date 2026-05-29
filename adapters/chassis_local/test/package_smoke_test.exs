defmodule Chassis.Package.Local.SmokeTest do
  use ExUnit.Case, async: true

  test "package marker is compiled" do
    assert Chassis.Package.Local.package_ref() == "chassis_local"
    assert Chassis.Package.Local.implemented?()
  end
end
