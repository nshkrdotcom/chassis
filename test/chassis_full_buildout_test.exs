defmodule ChassisFullBuildoutTest do
  use ExUnit.Case, async: true

  test "root CLI exposes final smoke commands" do
    assert {0, output} =
             Chassis.CLI.dispatch_to_output([
               "stack.deploy",
               "extravaganza",
               "--profile",
               "profile:monolith",
               "--env",
               "dev",
               "--json"
             ])

    assert output =~ "\"status\":\"active\""
  end

  test "evolution and model fixture commands are available" do
    assert {0, evolution} =
             Chassis.CLI.dispatch_to_output([
               "evolution.fixture",
               "--scenario",
               "source_level_patch_success",
               "--json"
             ])

    assert evolution =~ "\"final_state\":\"committed\""

    assert {0, model} =
             Chassis.CLI.dispatch_to_output([
               "model.fixture",
               "--scenario",
               "hf_weight_materialization",
               "--json"
             ])

    assert model =~ "\"digest_verified\":true"
  end
end
