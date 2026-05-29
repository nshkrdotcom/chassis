defmodule Chassis.Package.Fixtures.SmokeTest do
  use ExUnit.Case, async: true

  test "package marker is compiled" do
    assert Chassis.Package.Fixtures.package_ref() == "chassis_fixtures"
    assert Chassis.Package.Fixtures.implemented?()
  end
end
