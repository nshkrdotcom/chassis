defmodule Chassis.Package.Inventory.SmokeTest do
  use ExUnit.Case, async: true

  test "package marker is compiled" do
    assert Chassis.Package.Inventory.package_ref() == "chassis_inventory"
    assert Chassis.Package.Inventory.implemented?()
  end
end
