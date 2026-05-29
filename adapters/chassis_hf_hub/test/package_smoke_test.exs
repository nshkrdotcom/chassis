defmodule Chassis.Package.HfHub.SmokeTest do
  use ExUnit.Case, async: true

  test "package marker is compiled" do
    assert Chassis.Package.HfHub.package_ref() == "chassis_hf_hub"
    assert Chassis.Package.HfHub.implemented?()
  end
end
