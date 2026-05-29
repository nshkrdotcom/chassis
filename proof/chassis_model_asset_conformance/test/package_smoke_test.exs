defmodule Chassis.Package.ModelAssetConformance.SmokeTest do
  use ExUnit.Case, async: true

  test "package marker is compiled" do
    assert Chassis.Package.ModelAssetConformance.package_ref() ==
             "chassis_model_asset_conformance"

    assert Chassis.Package.ModelAssetConformance.implemented?()
  end
end
