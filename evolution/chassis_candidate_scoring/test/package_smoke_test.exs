defmodule Chassis.Package.CandidateScoring.SmokeTest do
  use ExUnit.Case, async: true

  test "package marker is compiled" do
    assert Chassis.Package.CandidateScoring.package_ref() == "chassis_candidate_scoring"
    assert Chassis.Package.CandidateScoring.implemented?()
  end
end
