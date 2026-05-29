defmodule Chassis.Package.Core.SmokeTest do
  use ExUnit.Case, async: true

  test "package marker is compiled" do
    assert Chassis.Package.Core.package_ref() == "chassis_core"
    assert Chassis.Package.Core.implemented?()
  end
end
