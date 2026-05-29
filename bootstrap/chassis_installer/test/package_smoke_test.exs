defmodule Chassis.Package.Installer.SmokeTest do
  use ExUnit.Case, async: true

  test "package marker is compiled" do
    assert Chassis.Package.Installer.package_ref() == "chassis_installer"
    assert Chassis.Package.Installer.implemented?()
  end
end
