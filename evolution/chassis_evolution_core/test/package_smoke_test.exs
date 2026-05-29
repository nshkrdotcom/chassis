defmodule Chassis.Package.EvolutionCore.SmokeTest do
  use ExUnit.Case, async: true

  test "package marker is compiled" do
    assert Chassis.Package.EvolutionCore.package_ref() == "chassis_evolution_core"
    assert Chassis.Package.EvolutionCore.implemented?()
  end
end
