defmodule Chassis.Workspace.RootCLIStaticResponsePathRegressionTest do
  @moduledoc """
  Workspace-root mirror of
  `manager/chassis_cli/test/static_response_path_regression_test.exs`.

  The escript `chassis` boots into the workspace-root `Chassis.CLI` module
  (per the root `mix.exs` `escript: [main_module: Chassis.CLI, ...]`). This
  test proves the workspace-root copy of `Chassis.CLI` is a strict
  not-implemented dispatcher and contains zero static response payloads.

  This test must remain green for the entire buildout.
  """
  use ExUnit.Case, async: true

  @sample_commands [
    "stack.deploy",
    "stack.status",
    "stack.rollback",
    "stack.diff",
    "host.inventory",
    "host.inspect",
    "host.swap",
    "host.probe",
    "node.doctor",
    "node.bootstrap",
    "node.trial",
    "app.list",
    "app.deploy",
    "app.rollback",
    "keys.list",
    "env.list",
    "env.show",
    "proof.run",
    "evolution.start",
    "evolution.status",
    "hardware.validate",
    "model.materialize",
    "model.cache.list",
    "tensor.reload",
    "tensor.rollback",
    "boundary.scan",
    "boundary.conformance"
  ]

  describe "root Chassis.CLI is a strict not-implemented dispatcher" do
    test "stack.deploy refuses to fabricate status: active and receipt:deployment:smoke" do
      {code, payload} =
        Chassis.CLI.dispatch([
          "stack.deploy",
          "extravaganza",
          "--profile",
          "profile:monolith",
          "--env",
          "dev"
        ])

      assert code == 1
      assert payload.error == "not_implemented"
      assert payload.phase_gate == 11
      assert payload.package == :chassis_stack_manager
      refute Map.get(payload, :status) == "active"
      refute Map.has_key?(payload, :receipt_ref)
    end

    test "proof.run refuses to fabricate passed: 12, failed: 0" do
      {code, payload} = Chassis.CLI.dispatch(["proof.run"])
      assert code == 1
      assert payload.error == "not_implemented"
      refute Map.get(payload, :passed) == 12
      refute Map.get(payload, :failed) == 0
    end

    test "every documented command goes through Chassis.CLI.Command.*" do
      for command <- @sample_commands do
        {_code, payload} = Chassis.CLI.dispatch([command])
        assert is_map(payload)

        case payload do
          %{error: "not_implemented"} = err ->
            assert err.module =~ "Chassis.CLI.Command."
            assert is_atom(err.package)
            assert is_integer(err.phase_gate)

          %{} = ok ->
            assert ok[:command] == command,
                   "active root command #{command} did not stamp :command"
        end
      end
    end

    test "unknown command returns the structured unknown_command map" do
      {code, payload} = Chassis.CLI.dispatch(["totally.fake.command"])
      assert code == 1
      assert payload.error == "unknown_command"
      assert payload.command == "totally.fake.command"
      assert is_list(payload.known_commands)
    end

    test "empty argv returns help and lists every known command" do
      {code, payload} = Chassis.CLI.dispatch([])
      assert code == 0
      assert payload.command == "help"
      assert "stack.deploy" in payload.commands
      assert "proof.run" in payload.commands
    end

    test "json encoding embeds structured not-implemented payload, no static keys" do
      {code, output} = Chassis.CLI.dispatch_to_output(["stack.deploy", "--json"])
      assert code == 1
      assert output =~ ~s("error":"not_implemented")
      assert output =~ ~s("phase_gate":11)
      assert output =~ ~s("package":"chassis_stack_manager")
      refute output =~ ~s("status":"active")
      refute output =~ ~s("receipt_ref":"receipt:deployment:smoke")
    end
  end
end
