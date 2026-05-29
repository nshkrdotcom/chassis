defmodule Chassis.Package.Bootstrap.SmokeTest do
  use ExUnit.Case, async: true

  test "package marker is compiled" do
    assert Chassis.Package.Bootstrap.package_ref() == "chassis_bootstrap"
    assert Chassis.Package.Bootstrap.implemented?()
  end
end
