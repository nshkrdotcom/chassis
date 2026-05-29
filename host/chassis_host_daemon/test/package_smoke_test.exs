defmodule Chassis.Package.HostDaemon.SmokeTest do
  use ExUnit.Case, async: true

  test "package marker is compiled" do
    assert Chassis.Package.HostDaemon.package_ref() == "chassis_host_daemon"
    assert Chassis.Package.HostDaemon.implemented?()
  end
end
