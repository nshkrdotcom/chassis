defmodule Chassis.Package.TensorReload.SmokeTest do
  use ExUnit.Case, async: true

  test "package marker is compiled" do
    assert Chassis.Package.TensorReload.package_ref() == "chassis_tensor_reload"
    assert Chassis.Package.TensorReload.implemented?()
  end
end
