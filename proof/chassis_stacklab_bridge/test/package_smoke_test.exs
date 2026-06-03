defmodule Chassis.StackLab.Bridge.RunConformanceTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Chassis.Boundary.Envelope
  alias Chassis.Boundary.LocalAdapter
  alias Chassis.Boundary.RunConformance.{Request, Response}
  alias Chassis.StackLab.Bridge.RunConformance

  @proof_names [
    "chassis.boundary.local_adapter_equivalence.v1",
    "chassis.boundary.no_pid_payloads.v1",
    "chassis.boundary.no_raw_secret_payloads.v1",
    "chassis.boundary.codec_digest_stability.v1",
    "chassis.boundary.idempotency_required_for_mutations.v1",
    "chassis.boundary.citadel_fail_closed.v1",
    "chassis.deployment.profile_monolith_local",
    "chassis.deployment.profile_ternary_split_3_local",
    "chassis.deployment.profile_maximal_decoupled_local",
    "chassis.secrets.no_plaintext_in_receipts",
    "chassis.tenant.residency_enforcement",
    "chassis.metabolic.auto_rollback_on_pressure"
  ]

  test "run/1 delegates to the Chassis conformance catalog and returns proof rows" do
    assert {:ok, report} = RunConformance.run(tag: :chassis)

    assert report.passed == 12
    assert report.failed == 0
    assert report.skipped == 0
    assert Enum.map(report.proofs, & &1.name) == @proof_names
    assert Enum.all?(report.proofs, &(&1.status == :pass))
  end

  test "boundary local adapter executes RunConformance.call/2 and returns response DTO" do
    envelope =
      Envelope.new!(%{
        protocol_ref: "boundary:stacklab.chassis.run_conformance:v1",
        envelope_ref: "env:test:stacklab:run_conformance",
        tenant_ref: "tenant:dev",
        installation_ref: "installation:dev",
        actor_ref: "operator:test",
        system_actor_ref: "system:stacklab",
        trace_id: "trace:test:stacklab:run_conformance",
        payload: %Request{
          proof_refs: @proof_names,
          target_ref: "target:local",
          profile: "baseline"
        }
      })

    assert {:ok, response_envelope} =
             LocalAdapter.dispatch(envelope, protocol_module: RunConformance)

    assert %Response{} = response = response_envelope.payload
    assert response.status == "ok"
    assert response.passed == 12
    assert response.failed == 0
    assert Enum.map(response.proof_results, & &1.name) == @proof_names
  end

  test "mix chassis.proof.run emits structural JSON for StackLab" do
    output =
      capture_io(fn ->
        Mix.Tasks.Chassis.Proof.Run.run(["--tag", "chassis", "--json"])
      end)

    assert {:ok, decoded} = Jason.decode(output)
    assert decoded["passed"] == 12
    assert decoded["failed"] == 0
    assert decoded["skipped"] == 0
    assert Enum.map(decoded["proofs"], & &1["name"]) == @proof_names
  end
end
