defmodule Chassis.Package.Mesh.SmokeTest do
  use ExUnit.Case, async: true

  test "package marker is compiled" do
    assert Chassis.Package.Mesh.package_ref() == "chassis_mesh"
    assert Chassis.Package.Mesh.implemented?()
  end
end
