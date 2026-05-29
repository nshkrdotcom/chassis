defmodule Chassis.Package.Conformance.SmokeTest do
  use ExUnit.Case, async: true

  test "package marker is compiled" do
    assert Chassis.Package.Conformance.package_ref() == "chassis_conformance"
    assert Chassis.Package.Conformance.implemented?()
  end
end
