defmodule Chassis.Package.Systemd.SmokeTest do
  use ExUnit.Case, async: true

  test "package marker is compiled" do
    assert Chassis.Package.Systemd.package_ref() == "chassis_systemd"
    assert Chassis.Package.Systemd.implemented?()
  end
end
