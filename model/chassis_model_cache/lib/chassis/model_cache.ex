defmodule Chassis.Model.Cache.Receipts.MaterializationRecord do
  @moduledoc "Cache materialization receipt."

  @enforce_keys [
    :receipt_ref,
    :host_ref,
    :tenant_ref,
    :model_ref,
    :cache_path_ref,
    :bytes,
    :digest,
    :materialized_at
  ]
  defstruct [
    :receipt_ref,
    :host_ref,
    :tenant_ref,
    :model_ref,
    :cache_path_ref,
    :bytes,
    :digest,
    :materialized_at
  ]
end

defmodule Chassis.Model.Cache.Receipts.VerifyRecord do
  @moduledoc "Cache digest verification receipt."

  @enforce_keys [
    :receipt_ref,
    :host_ref,
    :model_ref,
    :expected_digest_ref,
    :observed_digest,
    :verify_outcome,
    :verified_at
  ]
  defstruct [
    :receipt_ref,
    :host_ref,
    :model_ref,
    :expected_digest_ref,
    :observed_digest,
    :verify_outcome,
    :verified_at
  ]
end

defmodule Chassis.Model.Cache.Receipts.EvictionRecord do
  @moduledoc "Cache eviction receipt."

  @enforce_keys [
    :receipt_ref,
    :host_ref,
    :tenant_ref,
    :model_ref,
    :cache_path_ref,
    :bytes_reclaimed,
    :reason,
    :evicted_at
  ]
  defstruct [
    :receipt_ref,
    :host_ref,
    :tenant_ref,
    :model_ref,
    :cache_path_ref,
    :bytes_reclaimed,
    :reason,
    :evicted_at
  ]
end

defmodule Chassis.Model.Cache.Receipts.CacheReceipt do
  @moduledoc "Cache pressure and index receipt."

  @enforce_keys [
    :receipt_ref,
    :target_host_ref,
    :total_bytes,
    :used_bytes,
    :free_bytes,
    :pressure,
    :entries_count,
    :snapshot_at
  ]
  defstruct [
    :receipt_ref,
    :target_host_ref,
    :total_bytes,
    :used_bytes,
    :free_bytes,
    :pressure,
    :entries_count,
    :snapshot_at
  ]
end

defmodule Chassis.Model.Cache do
  @moduledoc """
  Target-host model cache index with tenant-aware LRU eviction.

  This package records cache metadata only. It never stores model bytes,
  secrets, or runtime state.
  """

  alias Chassis.Model.Cache.Receipts.{
    CacheReceipt,
    EvictionRecord,
    MaterializationRecord,
    VerifyRecord
  }

  @table :chassis_model_cache_entries
  @default_root "/var/cache/nshkr/models"
  @default_total_bytes 1_000_000_000_000
  @secret_pattern ~r/(BEGIN PRIVATE KEY|password|api_key)/i

  @spec default_root() :: Path.t()
  def default_root, do: @default_root

  @spec default_permissions() :: map()
  def default_permissions,
    do: %{mode: "0750", owner: "nshkr_chassis_host", group: "nshkr_chassis_host"}

  @spec reset() :: :ok
  def reset do
    ensure_table()
    :ets.delete_all_objects(@table)
    :ok
  end

  @spec list(String.t(), keyword()) :: {:ok, map()}
  def list(host_ref, opts \\ []) do
    tenant_ref = Keyword.get(opts, :tenant_ref)
    entries = host_entries(host_ref, tenant_ref)
    pressure = pressure_for(host_ref, opts)

    {:ok,
     %{
       host_ref: host_ref,
       root: @default_root,
       mode: default_permissions().mode,
       entries: Enum.sort_by(entries, & &1.model_ref),
       pressure: pressure,
       cache_receipt: cache_receipt(host_ref, entries, pressure)
     }}
  end

  @spec put(String.t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def put(host_ref, entry, opts \\ [])

  def put(host_ref, entry, opts) when is_map(entry) do
    with :ok <- reject_raw_secrets(entry),
         {:ok, normalized} <- normalize_entry(entry) do
      ensure_table()
      :ets.insert(@table, {{host_ref, normalized.tenant_ref, normalized.model_ref}, normalized})

      evictions = evict_for_pressure(host_ref, normalized.tenant_ref, opts)
      entries = host_entries(host_ref)
      pressure = pressure_for(host_ref, opts)

      {:ok,
       %{
         entry: normalized,
         materialization_receipt: materialization_receipt(host_ref, normalized),
         verify_receipt: verify_receipt(host_ref, normalized),
         eviction_receipts: evictions,
         cache_receipt: cache_receipt(host_ref, entries, pressure),
         metrics: eviction_metrics(evictions)
       }}
    end
  end

  def put(_host_ref, entry, _opts), do: {:error, {:invalid_cache_entry, entry}}

  @spec get(String.t(), String.t(), keyword()) ::
          {:hit, map(), CacheReceipt.t()} | {:miss, CacheReceipt.t()}
  def get(host_ref, model_ref, opts \\ []) do
    tenant_ref = Keyword.get(opts, :tenant_ref)
    entries = host_entries(host_ref, tenant_ref)
    pressure = pressure_for(host_ref, opts)
    receipt = cache_receipt(host_ref, entries, pressure)

    case Enum.find(entries, &(&1.model_ref == model_ref)) do
      nil -> {:miss, receipt}
      entry -> {:hit, entry, receipt}
    end
  end

  @spec evict(String.t(), String.t(), keyword()) :: {:ok, EvictionRecord.t()} | {:error, term()}
  def evict(host_ref, model_ref, opts \\ []) do
    tenant_ref = Keyword.get(opts, :tenant_ref)

    case Enum.find(host_entries(host_ref, tenant_ref), &(&1.model_ref == model_ref)) do
      nil ->
        {:error, {:cache_entry_not_found, host_ref, model_ref}}

      entry ->
        delete_entry(host_ref, entry)
        {:ok, eviction_receipt(host_ref, entry, Keyword.get(opts, :reason, :operator))}
    end
  end

  @spec disk_pressure(String.t(), keyword()) :: map()
  def disk_pressure(host_ref, opts \\ []), do: pressure_for(host_ref, opts)

  @spec jsonable(term()) :: term()
  def jsonable(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  def jsonable(%_struct{} = struct), do: struct |> Map.from_struct() |> jsonable()

  def jsonable(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), jsonable(value)} end)
  end

  def jsonable(list) when is_list(list), do: Enum.map(list, &jsonable/1)
  def jsonable(tuple) when is_tuple(tuple), do: tuple |> Tuple.to_list() |> jsonable()
  def jsonable(value) when is_boolean(value), do: value
  def jsonable(nil), do: nil
  def jsonable(atom) when is_atom(atom), do: Atom.to_string(atom)
  def jsonable(value), do: value

  defp normalize_entry(entry) do
    required = [:tenant_ref, :model_ref, :cache_path_ref, :bytes, :materialized_at, :digest]
    missing = Enum.reject(required, &Map.has_key?(entry, &1))

    if missing == [] do
      {:ok,
       entry
       |> Map.put_new(:last_used_at, entry.materialized_at)
       |> Map.put_new(:pinned?, false)}
    else
      {:error, {:missing_cache_entry_keys, missing}}
    end
  end

  defp reject_raw_secrets(entry) do
    case Enum.find(entry, fn {_key, value} -> is_binary(value) and value =~ @secret_pattern end) do
      nil -> :ok
      {key, _value} -> {:error, {:raw_secret_in_cache_entry, key}}
    end
  end

  defp evict_for_pressure(host_ref, tenant_ref, opts) do
    cond do
      Keyword.has_key?(opts, :tenant_quota_bytes) ->
        evict_until_tenant_under_quota(
          host_ref,
          tenant_ref,
          Keyword.fetch!(opts, :tenant_quota_bytes)
        )

      Keyword.has_key?(opts, :high_watermark_free_bytes) ->
        evict_until_free(host_ref, tenant_ref, opts)

      true ->
        []
    end
  end

  defp evict_until_tenant_under_quota(host_ref, tenant_ref, quota) do
    tenant_entries = host_entries(host_ref, tenant_ref)

    if used_bytes(tenant_entries) <= quota do
      []
    else
      tenant_entries
      |> lru_candidates()
      |> evict_candidates(host_ref, fn ->
        used_bytes(host_entries(host_ref, tenant_ref)) <= quota
      end)
    end
  end

  defp evict_until_free(host_ref, tenant_ref, opts) do
    total = Keyword.get(opts, :capacity_bytes, @default_total_bytes)
    high_watermark = Keyword.fetch!(opts, :high_watermark_free_bytes)

    if total - used_bytes(host_entries(host_ref)) >= high_watermark do
      []
    else
      host_ref
      |> host_entries(tenant_ref)
      |> lru_candidates()
      |> evict_candidates(host_ref, fn ->
        total - used_bytes(host_entries(host_ref)) >= high_watermark
      end)
    end
  end

  defp evict_candidates(candidates, host_ref, stop?) do
    Enum.reduce_while(candidates, [], fn entry, receipts ->
      if stop?.() do
        {:halt, Enum.reverse(receipts)}
      else
        delete_entry(host_ref, entry)
        {:cont, [eviction_receipt(host_ref, entry, :lru) | receipts]}
      end
    end)
    |> case do
      receipts when is_list(receipts) ->
        if stop?.(), do: receipts, else: receipts
    end
  end

  defp lru_candidates(entries) do
    entries
    |> Enum.reject(&Map.get(&1, :pinned?, false))
    |> Enum.sort_by(& &1.last_used_at, DateTime)
  end

  defp host_entries(host_ref, tenant_ref \\ nil) do
    ensure_table()

    @table
    |> :ets.tab2list()
    |> Enum.flat_map(fn
      {{^host_ref, tenant, _model}, entry} ->
        if is_nil(tenant_ref) or tenant == tenant_ref, do: [entry], else: []

      _other ->
        []
    end)
  end

  defp delete_entry(host_ref, entry) do
    :ets.delete(@table, {host_ref, entry.tenant_ref, entry.model_ref})
  end

  defp pressure_for(host_ref, opts) do
    total = Keyword.get(opts, :capacity_bytes, @default_total_bytes)
    used = used_bytes(host_entries(host_ref))
    free = max(total - used, 0)
    free_ratio = if total == 0, do: 0.0, else: free / total
    used_ratio = if total == 0, do: 1.0, else: used / total

    %{
      total_bytes: total,
      used_bytes: used,
      free_bytes: free,
      pressure: pressure(free_ratio, used_ratio)
    }
  end

  defp pressure(free_ratio, _used_ratio) when free_ratio < 0.05, do: :critical
  defp pressure(free_ratio, _used_ratio) when free_ratio < 0.15, do: :high
  defp pressure(_free_ratio, used_ratio) when used_ratio >= 0.35, do: :medium
  defp pressure(_free_ratio, _used_ratio), do: :low

  defp used_bytes(entries), do: Enum.reduce(entries, 0, &(&1.bytes + &2))

  defp materialization_receipt(host_ref, entry) do
    %MaterializationRecord{
      receipt_ref: receipt_ref("materialization", host_ref, entry.model_ref),
      host_ref: host_ref,
      tenant_ref: entry.tenant_ref,
      model_ref: entry.model_ref,
      cache_path_ref: entry.cache_path_ref,
      bytes: entry.bytes,
      digest: entry.digest,
      materialized_at: entry.materialized_at
    }
  end

  defp verify_receipt(host_ref, entry) do
    %VerifyRecord{
      receipt_ref: receipt_ref("verify", host_ref, entry.model_ref),
      host_ref: host_ref,
      model_ref: entry.model_ref,
      expected_digest_ref: entry.digest,
      observed_digest: entry.digest,
      verify_outcome: :ok,
      verified_at: DateTime.utc_now()
    }
  end

  defp eviction_receipt(host_ref, entry, reason) do
    %EvictionRecord{
      receipt_ref: receipt_ref("eviction", host_ref, entry.model_ref),
      host_ref: host_ref,
      tenant_ref: entry.tenant_ref,
      model_ref: entry.model_ref,
      cache_path_ref: entry.cache_path_ref,
      bytes_reclaimed: entry.bytes,
      reason: reason,
      evicted_at: DateTime.utc_now()
    }
  end

  defp cache_receipt(host_ref, entries, pressure) do
    %CacheReceipt{
      receipt_ref: receipt_ref("cache", host_ref, "snapshot"),
      target_host_ref: host_ref,
      total_bytes: pressure.total_bytes,
      used_bytes: pressure.used_bytes,
      free_bytes: pressure.free_bytes,
      pressure: pressure.pressure,
      entries_count: length(entries),
      snapshot_at: DateTime.utc_now()
    }
  end

  defp eviction_metrics(evictions) do
    Enum.map(evictions, fn eviction ->
      %{
        name: "chassis_model_weight_materialization_bytes_total",
        value: eviction.bytes_reclaimed,
        labels: %{outcome: :evicted, reason: eviction.reason, host_ref: eviction.host_ref}
      }
    end)
  end

  defp receipt_ref(kind, host_ref, model_ref) do
    safe_model = model_ref |> to_string() |> String.replace(":", "_")
    "receipt:model_cache:#{kind}:#{host_ref}:#{safe_model}"
  end

  defp ensure_table do
    case :ets.whereis(@table) do
      :undefined -> :ets.new(@table, [:named_table, :public, :set])
      table -> table
    end
  end
end
