defmodule Chassis.Package.EvolutionConformance.SmokeTest do
  use ExUnit.Case, async: true

  test "package marker is compiled" do
    assert Chassis.Package.EvolutionConformance.package_ref() == "chassis_evolution_conformance"
    assert Chassis.Package.EvolutionConformance.implemented?()
  end
end
