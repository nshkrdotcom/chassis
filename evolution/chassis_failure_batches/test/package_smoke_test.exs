defmodule Chassis.Package.FailureBatches.SmokeTest do
  use ExUnit.Case, async: true

  test "package marker is compiled" do
    assert Chassis.Package.FailureBatches.package_ref() == "chassis_failure_batches"
    assert Chassis.Package.FailureBatches.implemented?()
  end
end
