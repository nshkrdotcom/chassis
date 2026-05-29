defmodule Chassis.Package.SecretSops.SmokeTest do
  use ExUnit.Case, async: true

  test "package marker is compiled" do
    assert Chassis.Package.SecretSops.package_ref() == "chassis_secret_sops"
    assert Chassis.Package.SecretSops.implemented?()
  end
end
