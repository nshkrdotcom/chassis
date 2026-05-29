defmodule Chassis.Package.Environments.SmokeTest do
  use ExUnit.Case, async: true

  test "package marker is compiled" do
    assert Chassis.Package.Environments.package_ref() == "chassis_environments"
    assert Chassis.Package.Environments.implemented?()
  end
end
