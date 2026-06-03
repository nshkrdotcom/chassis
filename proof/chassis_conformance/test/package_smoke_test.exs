defmodule Chassis.ConformanceTest do
  use ExUnit.Case, async: false

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

  test "catalog exposes the exact Phase 21 proof set in a stable order" do
    assert Enum.map(Chassis.Conformance.catalog(), & &1.name) == @proof_names
    assert Enum.all?(Chassis.Conformance.catalog(), &is_function(&1.run, 0))
  end

  test "run/1 executes every proof and returns evidence, not static pass counts" do
    assert {:ok, report} = Chassis.Conformance.run(tag: :chassis)

    assert report.passed == 12
    assert report.failed == 0
    assert report.skipped == 0
    assert Enum.map(report.proofs, & &1.name) == @proof_names

    for proof <- report.proofs do
      assert proof.status == :pass
      assert is_integer(proof.duration_us)
      assert proof.duration_us >= 0
      assert is_map(proof.evidence)
      assert map_size(proof.evidence) > 0
      refute inspect(proof.evidence) =~ "PRIVATE KEY BYTES"
      refute inspect(proof.evidence) =~ "-----BEGIN"
    end
  end

  test "run/1 can target one proof and unknown proof names fail closed" do
    assert {:ok, report} =
             Chassis.Conformance.run(proof_refs: ["chassis.boundary.codec_digest_stability.v1"])

    assert report.passed == 1

    assert [%{name: "chassis.boundary.codec_digest_stability.v1", status: :pass}] =
             report.proofs

    assert {:error, {:unknown_proofs, ["chassis.nope"]}} =
             Chassis.Conformance.run(proof_refs: ["chassis.nope"])
  end
end
