defmodule Chassis.Package.Cli.SmokeTest do
  use ExUnit.Case, async: true

  test "package marker is compiled" do
    assert Chassis.Package.Cli.package_ref() == "chassis_cli"
    assert Chassis.Package.Cli.implemented?()
  end
end
