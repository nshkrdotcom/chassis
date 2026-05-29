defmodule Chassis.Package.SwapSupervisor.SmokeTest do
  use ExUnit.Case, async: true

  test "package marker is compiled" do
    assert Chassis.Package.SwapSupervisor.package_ref() == "chassis_swap_supervisor"
    assert Chassis.Package.SwapSupervisor.implemented?()
  end
end
