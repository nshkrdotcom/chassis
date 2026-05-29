defmodule Chassis.Package.SecretEnv.SmokeTest do
  use ExUnit.Case, async: true

  test "package marker is compiled" do
    assert Chassis.Package.SecretEnv.package_ref() == "chassis_secret_env"
    assert Chassis.Package.SecretEnv.implemented?()
  end
end
