defmodule Chassis.Package.Metrics.SmokeTest do
  use ExUnit.Case, async: true

  test "package marker is compiled" do
    assert Chassis.Package.Metrics.package_ref() == "chassis_metrics"
    assert Chassis.Package.Metrics.implemented?()
  end
end
