defmodule Chassis.Model.WeightMaterializerTest do
  use ExUnit.Case, async: true

  alias Chassis.Model.Manifest
  alias Chassis.Model.WeightMaterializer
  alias Chassis.Model.WeightSource
  alias Chassis.Model.Receipts.{MaterializationRecord, VerifyRecord}

  test "hf hub materialization verifies digest without BEAM control-channel bytes" do
    assert {:ok, manifest} = Manifest.for_model("model:hf:qwen3-small-fixture")
    expected_digest = Manifest.primary_digest(manifest)

    assert {:ok, report} =
             WeightMaterializer.materialize(%{
               tenant_ref: "tenant:dev",
               installation_ref: "installation:dev",
               model_ref: manifest.model_ref,
               target_host_ref: "host:gpu-fixture",
               source_strategy: :hf_hub,
               expected_digest_ref: expected_digest,
               bandwidth_class: :priority,
               verify_sha256?: true,
               dry_run?: true
             })

    assert report.digest_verified == true
    assert report.digest_verification == :ok
    assert report.bytes_via_beam_control? == false
    assert report.control_channel_bytes == 0
    assert report.bandwidth_class == :priority
    assert report.cache_path_ref =~ "/var/cache/nshkr/models/"
    assert report.cache_write_event.status == :deferred_phase_39

    assert %MaterializationRecord{observed_digest: ^expected_digest} =
             report.materialization_record

    assert %VerifyRecord{verify_outcome: :ok} = report.verify_record
    refute inspect(report.envelope) =~ ".safetensors-bytes"
  end

  test "digest mismatch is rejected and never marks digest_verified true" do
    assert {:error, {:digest_mismatch, details}} =
             WeightMaterializer.materialize(%{
               tenant_ref: "tenant:dev",
               installation_ref: "installation:dev",
               model_ref: "model:hf:qwen3-small-fixture",
               target_host_ref: "host:gpu-fixture",
               source_strategy: :hf_hub,
               expected_digest_ref: "sha256:bad",
               bandwidth_class: :bulk,
               verify_sha256?: true,
               dry_run?: true
             })

    assert details.digest_verified == false
    assert details.verify_record.verify_outcome == :mismatch
    assert details.materialization_record.digest_verified == :mismatch
    assert details.control_channel_bytes == 0
  end

  test "resumes from partial target-side download" do
    assert {:ok, manifest} = Manifest.for_model("model:hf:qwen3-small-fixture")

    assert {:ok, report} =
             WeightMaterializer.materialize(%{
               tenant_ref: "tenant:dev",
               installation_ref: "installation:dev",
               model_ref: manifest.model_ref,
               target_host_ref: "host:gpu-fixture",
               source_strategy: :hf_hub,
               expected_digest_ref: Manifest.primary_digest(manifest),
               bandwidth_class: :bulk,
               verify_sha256?: true,
               dry_run?: true,
               partial_bytes: 1_024
             })

    assert report.resumed_from_partial?
    assert report.bytes_materialized == manifest.total_bytes
    assert report.materialization_record.duration_ms > 0
  end

  test "source resolution covers local, shared, and artifact mirror strategies" do
    for strategy <- [:local_cache, :shared_cache, :artifact_mirror] do
      assert module = WeightMaterializer.resolve_source(strategy)

      assert {:ok, result} =
               module.fetch(
                 %{
                   model_ref: "model:hf:qwen3-small-fixture",
                   target_host_ref: "host:gpu-fixture",
                   cache_path_ref: "/var/cache/nshkr/models/qwen3-small-fixture.safetensors",
                   expected_digest_ref: Manifest.fixture_digest("model:hf:qwen3-small-fixture"),
                   bandwidth_class: :bulk
                 },
                 dry_run: true
               )

      assert result.control_channel_bytes == 0
      assert result.observed_digest == Manifest.fixture_digest("model:hf:qwen3-small-fixture")
    end
  end

  test "invalid requests and unknown strategies fail closed" do
    assert {:error, {:missing_required_request_keys, [:target_host_ref]}} =
             WeightMaterializer.materialize(%{
               tenant_ref: "tenant:dev",
               installation_ref: "installation:dev",
               model_ref: "model:hf:qwen3-small-fixture",
               source_strategy: :hf_hub,
               expected_digest_ref: Manifest.fixture_digest("model:hf:qwen3-small-fixture"),
               bandwidth_class: :bulk
             })

    assert {:error, {:unknown_source_strategy, :torrent}} =
             WeightMaterializer.resolve_source(:torrent)

    assert {:error, {:unknown_model, "model:hf:missing"}} = Manifest.for_model("model:hf:missing")
  end

  test "weight source behaviour rejects byte payloads in the request envelope" do
    assert {:error, {:beam_control_bytes_forbidden, :weight_bytes}} =
             WeightSource.validate_fetch_request(%{
               model_ref: "model:hf:qwen3-small-fixture",
               target_host_ref: "host:gpu-fixture",
               cache_path_ref: "/var/cache/nshkr/models/qwen3-small-fixture.safetensors",
               expected_digest_ref: Manifest.fixture_digest("model:hf:qwen3-small-fixture"),
               bandwidth_class: :bulk,
               weight_bytes: <<1, 2, 3>>
             })
  end
end
