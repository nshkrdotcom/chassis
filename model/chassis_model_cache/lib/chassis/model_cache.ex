defmodule Chassis.Model.Cache do
  @moduledoc "Target-host model cache index."
  def list(host_ref, _opts \\ []),
    do: {:ok, %{host_ref: host_ref, entries: [], root: "/var/cache/nshkr/models", mode: "0750"}}

  def put(entry), do: {:ok, Map.put(entry, :cache_receipt_ref, "receipt:model_cache:smoke")}
  def evict(entry), do: {:ok, Map.put(entry, :evicted?, true)}
end

for record <- [MaterializationRecord, VerifyRecord, EvictionRecord, CacheReceipt] do
  defmodule Module.concat(Chassis.Model.Cache.Receipts, record) do
    @moduledoc "Model cache receipt."
    defstruct [:receipt_ref, :host_ref, :payload]
  end
end
