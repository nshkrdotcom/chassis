defmodule Chassis.Package.K8s.SmokeTest do
  use ExUnit.Case, async: true

  test "package marker is compiled" do
    assert Chassis.Package.K8s.package_ref() == "chassis_k8s"
    assert Chassis.Package.K8s.implemented?()
  end
end
