defmodule Chassis.Receipts do
  @moduledoc "Receipts with bounded redaction."

  @sensitive_fragments ~w(secret password private_key material token credential)

  @spec redact(term()) :: term()
  def redact(map) when is_map(map) do
    Map.new(map, fn {key, value} ->
      if sensitive_key?(key), do: {key, "[REDACTED]"}, else: {key, redact(value)}
    end)
  end

  def redact(list) when is_list(list), do: Enum.map(list, &redact/1)
  def redact(value), do: value

  @spec new_ref(String.t()) :: String.t()
  def new_ref(prefix),
    do: prefix <> ":" <> Base.encode16(:crypto.strong_rand_bytes(4), case: :lower)

  defp sensitive_key?(key) do
    downcased = key |> to_string() |> String.downcase()
    Enum.any?(@sensitive_fragments, &String.contains?(downcased, &1))
  end
end

defmodule Chassis.Receipts.Store do
  @moduledoc "Receipt store behaviour."
  @callback put(map()) :: {:ok, map()} | {:error, term()}
  @callback get(String.t()) :: {:ok, map()} | {:error, :not_found}
  @callback list(keyword()) :: [map()]
end

defmodule Chassis.Receipts.Store.Memory do
  @moduledoc "ETS-backed receipt store plus JSONL-like appender for dev."
  @table :chassis_receipts_memory

  @spec put(map()) :: {:ok, map()}
  def put(receipt) when is_map(receipt) do
    ensure_table()

    redacted =
      Chassis.Receipts.redact(
        Map.put_new(receipt, :receipt_ref, Chassis.Receipts.new_ref("receipt"))
      )

    :ets.insert(@table, {redacted.receipt_ref, redacted})
    append_jsonl(redacted)
    {:ok, redacted}
  end

  @spec get(String.t()) :: {:ok, map()} | {:error, :not_found}
  def get(ref) do
    ensure_table()

    case :ets.lookup(@table, ref) do
      [{^ref, receipt}] -> {:ok, receipt}
      [] -> {:error, :not_found}
    end
  end

  @spec list(keyword()) :: [map()]
  def list(_opts \\ []) do
    ensure_table()
    @table |> :ets.tab2list() |> Enum.map(fn {_ref, receipt} -> receipt end)
  end

  @spec clear() :: :ok
  def clear do
    ensure_table()
    :ets.delete_all_objects(@table)
    :ok
  end

  @spec put_smoke() :: {:ok, map()}
  def put_smoke, do: put(%{kind: :smoke, secret_ref: "secret:ssh_key:test"})

  defp ensure_table do
    case :ets.info(@table) do
      :undefined -> :ets.new(@table, [:named_table, :public, read_concurrency: true])
      _info -> @table
    end
  end

  defp append_jsonl(receipt) do
    path = Path.expand("~/.cache/chassis/receipts/dev.jsonl")
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, inspect(receipt) <> "\n", [:append])
  end
end

defmodule Chassis.Receipts.Store.AshPostgres do
  @moduledoc "AshPostgres-compatible facade. Uses memory backend in local smoke."
  defdelegate put(receipt), to: Chassis.Receipts.Store.Memory
  defdelegate get(ref), to: Chassis.Receipts.Store.Memory
  defdelegate list(opts \\ []), to: Chassis.Receipts.Store.Memory
end

for module <- [
      DeploymentRecord,
      ProvisioningRecord,
      RollbackRecord,
      KeyRotationRecord,
      MaterializationRecord,
      BoundaryRecord,
      TenantAwareDeploymentReceipt,
      AITraceReceipt
    ] do
  defmodule Module.concat(Chassis.Receipts, module) do
    @moduledoc "Typed receipt record."
    defstruct [
      :receipt_ref,
      :tenant_ref,
      :authority_ref,
      :trace_id,
      :kind,
      :payload,
      :inserted_at
    ]

    @type t :: %__MODULE__{
            receipt_ref: String.t() | nil,
            tenant_ref: String.t() | nil,
            authority_ref: String.t() | nil,
            trace_id: String.t() | nil,
            kind: atom() | nil,
            payload: map() | nil,
            inserted_at: DateTime.t() | nil
          }

    @spec new(map()) :: t()
    def new(attrs) when is_map(attrs) do
      struct(__MODULE__, Map.put_new(attrs, :inserted_at, DateTime.utc_now()))
    end

    @spec put(map()) :: {:ok, map()}
    def put(attrs) when is_map(attrs),
      do:
        attrs
        |> Map.put(:record_module, inspect(__MODULE__))
        |> Chassis.Receipts.Store.Memory.put()
  end
end
