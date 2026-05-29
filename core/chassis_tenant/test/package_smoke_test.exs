defmodule Chassis.Package.Tenant.SmokeTest do
  use ExUnit.Case, async: true

  test "package marker is compiled" do
    assert Chassis.Package.Tenant.package_ref() == "chassis_tenant"
    assert Chassis.Package.Tenant.implemented?()
  end
end
