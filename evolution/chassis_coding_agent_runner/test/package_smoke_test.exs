defmodule Chassis.Package.CodingAgentRunner.SmokeTest do
  use ExUnit.Case, async: true

  test "package marker is compiled" do
    assert Chassis.Package.CodingAgentRunner.package_ref() == "chassis_coding_agent_runner"
    assert Chassis.Package.CodingAgentRunner.implemented?()
  end
end
