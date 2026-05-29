defmodule Chassis.Package.SecretRefs.SmokeTest do
  use ExUnit.Case, async: true

  test "package marker is compiled" do
    assert Chassis.Package.SecretRefs.package_ref() == "chassis_secret_refs"
    assert Chassis.Package.SecretRefs.implemented?()
  end
end
