defmodule Chassis.Package.Receipts.SmokeTest do
  use ExUnit.Case, async: true

  test "package marker is compiled" do
    assert Chassis.Package.Receipts.package_ref() == "chassis_receipts"
    assert Chassis.Package.Receipts.implemented?()
  end
end
