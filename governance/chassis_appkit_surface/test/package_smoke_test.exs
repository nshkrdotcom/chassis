defmodule Chassis.Package.AppkitSurface.SmokeTest do
  use ExUnit.Case, async: true

  test "package marker is compiled" do
    assert Chassis.Package.AppkitSurface.package_ref() == "chassis_appkit_surface"
    assert Chassis.Package.AppkitSurface.implemented?()
  end
end
