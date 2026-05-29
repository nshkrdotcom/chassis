defmodule Chassis.Package.Releases.SmokeTest do
  use ExUnit.Case, async: true

  test "package marker is compiled" do
    assert Chassis.Package.Releases.package_ref() == "chassis_releases"
    assert Chassis.Package.Releases.implemented?()
  end
end
