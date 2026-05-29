defmodule Chassis.Package.CandidateRegistry.SmokeTest do
  use ExUnit.Case, async: true

  test "package marker is compiled" do
    assert Chassis.Package.CandidateRegistry.package_ref() == "chassis_candidate_registry"
    assert Chassis.Package.CandidateRegistry.implemented?()
  end
end
