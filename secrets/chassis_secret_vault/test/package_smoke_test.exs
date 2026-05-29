defmodule Chassis.Package.SecretVault.SmokeTest do
  use ExUnit.Case, async: true

  test "package marker is compiled" do
    assert Chassis.Package.SecretVault.package_ref() == "chassis_secret_vault"
    assert Chassis.Package.SecretVault.implemented?()
  end
end
