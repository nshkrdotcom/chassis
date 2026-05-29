defmodule Chassis.Package.EvolutionReceipts.SmokeTest do
  use ExUnit.Case, async: true

  test "package marker is compiled" do
    assert Chassis.Package.EvolutionReceipts.package_ref() == "chassis_evolution_receipts"
    assert Chassis.Package.EvolutionReceipts.implemented?()
  end
end
