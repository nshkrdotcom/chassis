defmodule Chassis.Package.ModelCache.SmokeTest do
  use ExUnit.Case, async: true

  test "package marker is compiled" do
    assert Chassis.Package.ModelCache.package_ref() == "chassis_model_cache"
    assert Chassis.Package.ModelCache.implemented?()
  end
end
