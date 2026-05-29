defmodule Chassis.Package.WeightMaterializer.SmokeTest do
  use ExUnit.Case, async: true

  test "package marker is compiled" do
    assert Chassis.Package.WeightMaterializer.package_ref() == "chassis_weight_materializer"
    assert Chassis.Package.WeightMaterializer.implemented?()
  end
end
