defmodule Chassis.CLI.StaticResponsePathRegressionTest do
  @moduledoc """
  Phase 0 permanent invariant per
  `0541_implementation_readiness_corrections.md` §3.3 / §6 invariant I2.

  This test must remain green for the entire buildout. It proves that:

  1. Every documented CLI command resolves to a `Chassis.CLI.Command.*` module,
     never to an in-CLI static payload.
  2. Commands whose underlying package has not been activated yet return the
     canonical `not_implemented` error map with non-zero exit code and the
     structured phase/package metadata required by `0541` §1 row 4.
  3. Unknown commands return a structured `unknown_command` error map.
  4. The CLI parses real argv; it does not accept random args as truthy.

  When a future phase activates a command, that phase MUST add the matching
  `Chassis.CLI.Command.*` module under the activated package and re-assert this
  test stays green by routing through the real module.
  """
  use ExUnit.Case, async: true

  alias Chassis.CLI

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
    "keys.add",
    "keys.list",
    "keys.show",
    "keys.rotate",
    "env.list",
    "env.show",
    "proof.run",
    "evolution.start",
    "evolution.stop",
    "evolution.status",
    "evolution.batches",
    "evolution.batch.show",
    "evolution.candidate.show",
    "evolution.score.show",
    "evolution.apply",
    "evolution.fixture",
    "hardware.validate",
    "model.materialize",
    "model.cache.list",
    "model.fixture",
    "tensor.reload",
    "tensor.rollback",
    "boundary.scan",
    "boundary.conformance"
  ]

  describe "every command resolves through a Chassis.CLI.Command.* module" do
    test "no command returns a static :ok success payload from the CLI itself" do
      for command <- @sample_commands do
        {code, payload} = CLI.dispatch([command, "--foo", "bar", "--baz", "qux"])

        # Either the command module is loaded (and we routed through it) — in
        # which case the CLI must NOT have synthesized a success on its own —
        # or the command module isn't loaded yet and we got the canonical
        # not_implemented map.
        assert is_map(payload),
               "command #{command}: expected map payload, got #{inspect(payload)}"

        case payload do
          %{error: "not_implemented"} = err ->
            assert code == 1, "not_implemented must use exit code 1, command=#{command}"
            assert err.command == command
            assert is_atom(err.package) or is_nil(err.package)
            assert is_integer(err.phase_gate) or is_nil(err.phase_gate)
            assert err.module =~ "Chassis.CLI.Command."

          %{} = ok_payload ->
            # An active command module returned a real payload. The router must
            # have stamped :command, which the static CLI never used to do.
            assert ok_payload[:command] == command,
                   "active command #{command} must return through Chassis.CLI.Command.* (got #{inspect(ok_payload)})"
        end
      end
    end

    test "unknown commands return the unknown_command error map with non-zero exit code" do
      {code, payload} = CLI.dispatch(["this.command.does.not.exist"])
      assert code == 1
      assert payload.error == "unknown_command"
      assert payload.command == "this.command.does.not.exist"
      assert is_list(payload.known_commands)
      assert "stack.deploy" in payload.known_commands
    end

    test "empty argv returns help payload with zero exit code" do
      {code, payload} = CLI.dispatch([])
      assert code == 0
      assert payload.command == "help"
      assert is_list(payload.commands)
      refute "help" in payload.commands
      refute "--help" in payload.commands
    end

    test "help command lists every routed command, never an in-CLI synthesized one" do
      {code, payload} = CLI.dispatch(["help"])
      assert code == 0
      assert payload.command == "help"

      for command <- @sample_commands do
        assert command in payload.commands, "help is missing #{command}"
      end
    end
  end

  describe "not-implemented metadata shape" do
    test "stack.deploy resolves to Chassis.CLI.Command.Stack.Deploy and returns the canonical error tuple shape" do
      {code, payload} =
        CLI.dispatch(["stack.deploy", "extravaganza", "--profile", "profile:monolith"])

      # Phase 11 hasn't run yet; the command module shouldn't exist.
      refute Code.ensure_loaded?(Chassis.CLI.Command.Stack.Deploy),
             "stack.deploy module must NOT be defined before Phase 11"

      assert code == 1
      assert payload.error == "not_implemented"
      assert payload.command == "stack.deploy"
      assert payload.phase_gate == 11
      assert payload.package == :chassis_stack_manager
      assert payload.module == "Chassis.CLI.Command.Stack.Deploy"
    end

    test "proof.run returns the canonical not_implemented payload tied to Phase 21" do
      {_code, payload} = CLI.dispatch(["proof.run"])
      assert payload.error == "not_implemented"
      assert payload.phase_gate == 21
      assert payload.package == :chassis_stacklab_bridge
    end
  end

  describe "router refuses to fabricate success" do
    test "stack.deploy never returns status: \"active\" with a baked receipt_ref" do
      {_code, payload} = CLI.dispatch(["stack.deploy", "extravaganza"])
      refute Map.get(payload, :status) == "active"
      refute Map.has_key?(payload, :receipt_ref)
    end

    test "proof.run never returns a hard-coded passed: 12, failed: 0 payload" do
      {_code, payload} = CLI.dispatch(["proof.run"])
      refute Map.get(payload, :passed) == 12
      refute Map.get(payload, :failed) == 0
    end

    test "hardware.validate never returns admission_outcome from the CLI itself" do
      {_code, payload} =
        CLI.dispatch(["hardware.validate", "--host", "host:cpu", "--runtime", "runtime:cuda"])

      refute Map.has_key?(payload, :admission_outcome)
    end

    test "tensor.reload never returns strategy_applied from the CLI itself" do
      {_code, payload} = CLI.dispatch(["tensor.reload"])
      refute Map.has_key?(payload, :strategy_applied)
    end
  end

  describe "encoding" do
    test "json encoding round-trips structural keys for the not-implemented payload" do
      {_code, payload} = CLI.dispatch(["stack.deploy"])
      json = Chassis.CLI.Encoding.encode(payload, json?: true)
      assert json =~ ~s("error":"not_implemented")
      assert json =~ ~s("command":"stack.deploy")
      assert json =~ ~s("phase_gate":11)
      assert json =~ ~s("package":"chassis_stack_manager")
    end

    test "human encoding labels errors with the ERROR prefix" do
      {_code, payload} = CLI.dispatch(["stack.deploy"])
      human = Chassis.CLI.Encoding.encode(payload, json?: false)
      assert human =~ "ERROR not_implemented"
    end
  end
end
