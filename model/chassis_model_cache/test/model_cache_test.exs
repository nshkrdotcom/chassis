defmodule Chassis.Model.CacheTest do
  use ExUnit.Case, async: false

  alias Chassis.Model.Cache

  alias Chassis.Model.Cache.Receipts.{
    CacheReceipt,
    EvictionRecord,
    MaterializationRecord,
    VerifyRecord
  }

  setup do
    Cache.reset()
    :ok
  end

  test "default root is locked to 0750 host-cache ownership" do
    assert Cache.default_root() == "/var/cache/nshkr/models"

    assert Cache.default_permissions() == %{
             mode: "0750",
             owner: "nshkr_chassis_host",
             group: "nshkr_chassis_host"
           }
  end

  test "put stores entries with materialization and verify receipts" do
    entry = entry("tenant:a", "model:hf:qwen3-small-fixture", 32)

    assert {:ok, result} = Cache.put("host:gpu-fixture", entry)

    assert %MaterializationRecord{model_ref: "model:hf:qwen3-small-fixture"} =
             result.materialization_receipt

    assert %VerifyRecord{verify_outcome: :ok} = result.verify_receipt
    assert result.cache_receipt.entries_count == 1

    assert {:ok, %{entries: [stored]}} = Cache.list("host:gpu-fixture")
    assert stored.model_ref == "model:hf:qwen3-small-fixture"
    assert stored.tenant_ref == "tenant:a"
  end

  test "LRU eviction at high watermark emits receipts and metrics" do
    old = entry("tenant:a", "model:old", 70, last_used_at: ~U[2026-01-01 00:00:00Z])
    new = entry("tenant:a", "model:new", 40, last_used_at: ~U[2026-02-01 00:00:00Z])

    assert {:ok, _} =
             Cache.put("host:gpu-fixture", old,
               capacity_bytes: 100,
               high_watermark_free_bytes: 20
             )

    assert {:ok, result} =
             Cache.put("host:gpu-fixture", new,
               capacity_bytes: 100,
               high_watermark_free_bytes: 20
             )

    assert [%EvictionRecord{model_ref: "model:old", reason: :lru}] = result.eviction_receipts

    assert Enum.any?(
             result.metrics,
             &(&1.name == "chassis_model_weight_materialization_bytes_total")
           )

    assert {:ok, %{entries: entries, pressure: %{pressure: :medium}}} =
             Cache.list("host:gpu-fixture", capacity_bytes: 100)

    assert Enum.map(entries, & &1.model_ref) == ["model:new"]
  end

  test "tenant partitions protect other tenants during eviction" do
    tenant_a_old = entry("tenant:a", "model:a-old", 70, last_used_at: ~U[2026-01-01 00:00:00Z])
    tenant_a_new = entry("tenant:a", "model:a-new", 40, last_used_at: ~U[2026-02-01 00:00:00Z])
    tenant_b = entry("tenant:b", "model:b", 70, last_used_at: ~U[2025-01-01 00:00:00Z])

    assert {:ok, _} = Cache.put("host:gpu-fixture", tenant_b, tenant_quota_bytes: 200)
    assert {:ok, _} = Cache.put("host:gpu-fixture", tenant_a_old, tenant_quota_bytes: 100)
    assert {:ok, result} = Cache.put("host:gpu-fixture", tenant_a_new, tenant_quota_bytes: 100)

    assert [%EvictionRecord{tenant_ref: "tenant:a", model_ref: "model:a-old"}] =
             result.eviction_receipts

    assert {:ok, %{entries: tenant_b_entries}} =
             Cache.list("host:gpu-fixture", tenant_ref: "tenant:b")

    assert Enum.map(tenant_b_entries, & &1.model_ref) == ["model:b"]
  end

  test "cache hit and miss emit cache receipts" do
    assert {:miss, %CacheReceipt{entries_count: 0, pressure: :low}} =
             Cache.get("host:gpu-fixture", "model:hf:qwen3-small-fixture")

    assert {:ok, _} =
             Cache.put("host:gpu-fixture", entry("tenant:a", "model:hf:qwen3-small-fixture", 32))

    assert {:hit, found, %CacheReceipt{entries_count: 1, pressure: :low}} =
             Cache.get("host:gpu-fixture", "model:hf:qwen3-small-fixture")

    assert found.model_ref == "model:hf:qwen3-small-fixture"
  end

  test "raw secrets are rejected before storage" do
    bad =
      entry("tenant:a", "model:hf:qwen3-small-fixture", 32)
      |> Map.put(:note, "api_key=password BEGIN PRIVATE KEY")

    assert {:error, {:raw_secret_in_cache_entry, :note}} = Cache.put("host:gpu-fixture", bad)
    assert {:ok, %{entries: []}} = Cache.list("host:gpu-fixture")
  end

  defp entry(tenant_ref, model_ref, bytes, opts \\ []) do
    %{
      tenant_ref: tenant_ref,
      model_ref: model_ref,
      cache_path_ref:
        "/var/cache/nshkr/models/#{String.replace(model_ref, ":", "_")}.safetensors",
      bytes: bytes,
      materialized_at: Keyword.get(opts, :materialized_at, ~U[2026-01-01 00:00:00Z]),
      last_used_at: Keyword.get(opts, :last_used_at, ~U[2026-01-01 00:00:00Z]),
      digest: "sha256:#{String.pad_trailing(Integer.to_string(bytes), 64, "0")}"
    }
  end
end
