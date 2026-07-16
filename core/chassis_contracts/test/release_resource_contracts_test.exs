defmodule Chassis.ReleaseResourceContractsTest do
  use ExUnit.Case, async: true

  alias Chassis.Contracts.{HealthObservation, ReleaseProfile, ResourceRequest}

  @digest "sha256:" <> String.duplicate("d", 64)

  test "release profile pins artifact, producer, contracts, migrations, and capabilities" do
    assert {:ok, profile} =
             ReleaseProfile.new(
               contract_version: 1,
               release_ref: "release://nshkr/0.1.0",
               artifact_ref: "artifact://nshkr/release-0.1.0",
               artifact_digest: @digest,
               version: "0.1.0",
               producer_revision: String.duplicate("a", 40),
               contract_revisions: %{"mezzanine.run-command.v1" => String.duplicate("b", 64)},
               migration_revisions: %{"mezzanine" => "20260715000100"},
               capability_refs: ["capability://nshkr/synapse-run"],
               created_at: ~U[2026-07-15 12:00:00Z]
             )

    assert profile.version == "0.1.0"
  end

  test "release profile rejects secret-bearing revision metadata" do
    assert {:error, :invalid_release_profile} =
             ReleaseProfile.new(
               contract_version: 1,
               release_ref: "release://nshkr/0.1.0",
               artifact_ref: "artifact://nshkr/release-0.1.0",
               artifact_digest: @digest,
               version: "0.1.0",
               producer_revision: String.duplicate("a", 40),
               contract_revisions: %{"api_key" => "sentinel-secret"},
               migration_revisions: %{"mezzanine" => "20260715000100"},
               capability_refs: [],
               created_at: ~U[2026-07-15 12:00:00Z]
             )

    assert {:error, :invalid_release_profile} =
             ReleaseProfile.new(
               contract_version: 1,
               release_ref: "release://nshkr/0.1.0",
               artifact_ref: "artifact://nshkr/release-0.1.0",
               artifact_digest: @digest,
               version: "0.1.0",
               producer_revision: String.duplicate("a", 40),
               contract_revisions: %{},
               migration_revisions: %{},
               capability_refs: [],
               created_at: ~U[2026-07-15 12:00:00Z],
               token: "sentinel-secret"
             )
  end

  test "resource request distinguishes local and remote target classes" do
    assert {:ok, request} =
             ResourceRequest.new(
               contract_version: 1,
               resource_request_ref: "resource-request://chassis/nshkr-1",
               tenant_ref: "tenant://acme",
               workload_ref: "workload://nshkr/monolith",
               release_ref: "release://nshkr/0.1.0",
               target_class: :local_host,
               cpu_millis: 2_000,
               memory_bytes: 4_294_967_296,
               disk_bytes: 10_737_418_240,
               volume_refs: ["volume://nshkr/postgres"],
               network_refs: ["network://nshkr/local"],
               constraints: %{"architecture" => "x86_64"}
             )

    assert request.target_class == "local_host"
  end

  test "ready health requires matching revisions and passed real checks" do
    attrs = %{
      contract_version: 1,
      observation_ref: "observation://chassis/nshkr-1",
      workload_ref: "workload://nshkr/monolith",
      release_ref: "release://nshkr/0.1.0",
      desired_revision: 2,
      observed_revision: 2,
      state: "ready",
      checks: [
        %{"check_ref" => "check://nshkr/process", "status" => "passed"},
        %{"check_ref" => "check://nshkr/appkit", "status" => "passed"}
      ],
      evidence_refs: ["evidence://chassis/nshkr-1"],
      observed_at: ~U[2026-07-15 12:01:00Z]
    }

    assert {:ok, observation} = HealthObservation.new(attrs)
    assert observation.state == "ready"

    assert {:error, :invalid_health_observation} =
             attrs |> Map.put(:observed_revision, 1) |> HealthObservation.new()

    assert {:error, :invalid_health_observation} =
             attrs
             |> Map.put(:checks, [%{"check_ref" => "check://nshkr/process", "status" => "failed"}])
             |> HealthObservation.new()
  end
end
