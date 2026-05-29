defmodule Chassis.Package.EvolutionContracts.SmokeTest do
  use ExUnit.Case, async: true

  test "package marker is compiled" do
    assert Chassis.Package.EvolutionContracts.package_ref() == "chassis_evolution_contracts"
    assert Chassis.Package.EvolutionContracts.implemented?()
  end
end
