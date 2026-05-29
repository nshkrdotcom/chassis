defmodule Chassis.Package.Ssh.SmokeTest do
  use ExUnit.Case, async: true

  test "package marker is compiled" do
    assert Chassis.Package.Ssh.package_ref() == "chassis_ssh"
    assert Chassis.Package.Ssh.implemented?()
  end
end
