defmodule Chassis.Package.Contracts.SmokeTest do
  use ExUnit.Case, async: true

  test "package marker is compiled" do
    assert Chassis.Package.Contracts.package_ref() == "chassis_contracts"
    assert Chassis.Package.Contracts.implemented?()
  end
end
