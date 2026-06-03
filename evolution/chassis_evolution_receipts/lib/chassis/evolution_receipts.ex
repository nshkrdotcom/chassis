defmodule Chassis.Evolution.Receipts.FailureBatchRecord do
  @moduledoc "Receipt row for a materialized failure batch."

  @fields [
    :receipt_ref,
    :failure_batch_ref,
    :tenant_ref,
    :installation_ref,
    :source,
    :evidence_refs,
    :summary,
    :redaction_posture,
    :flagged_by_ref,
    :batch_hint_ref,
    :source_event_ref,
    :source_region,
    :span_attributes,
    :projection_summary,
    :inserted_at
  ]

  @required_fields [
    :failure_batch_ref,
    :tenant_ref,
    :installation_ref,
    :source,
    :evidence_refs,
    :summary,
    :redaction_posture
  ]

  @sensitive_keys [
    :raw_transcript,
    :raw_body,
    :raw_bytes,
    :transcript,
    :body,
    :payload
  ]

  defstruct @fields

  @type t :: %__MODULE__{}

  @spec required_fields() :: [atom()]
  def required_fields, do: @required_fields

  @spec new!(map()) :: t()
  def new!(attrs) when is_map(attrs) do
    attrs =
      attrs
      |> normalize_allowed_fields()
      |> Map.put_new(:receipt_ref, receipt_ref(attrs))
      |> Map.put_new(:inserted_at, DateTime.utc_now())
      |> Map.put(:summary, sanitize_summary(Map.get(attrs, :summary)))
      |> Map.update(:evidence_refs, [], &List.wrap/1)

    assert_required!(attrs)
    struct!(__MODULE__, attrs)
  end

  defp normalize_allowed_fields(attrs) do
    allowed = MapSet.new(@fields)

    attrs
    |> Map.drop(@sensitive_keys)
    |> Map.new(fn
      {key, value} when is_binary(key) -> {String.to_existing_atom(key), value}
      {key, value} -> {key, value}
    end)
    |> Map.take(MapSet.to_list(allowed))
  end

  defp receipt_ref(%{receipt_ref: receipt_ref}) when is_binary(receipt_ref), do: receipt_ref
  defp receipt_ref(%{"receipt_ref" => receipt_ref}) when is_binary(receipt_ref), do: receipt_ref

  defp receipt_ref(attrs) do
    failure_batch_ref = Map.get(attrs, :failure_batch_ref) || Map.get(attrs, "failure_batch_ref")
    "receipt:failure_batch:#{failure_batch_ref}"
  end

  defp sanitize_summary(%{} = summary) do
    summary
    |> Map.drop(@sensitive_keys)
    |> Map.take([:bytes, :max_bytes, "bytes", "max_bytes"])
    |> normalize_summary_keys()
  end

  defp sanitize_summary(summary) when is_binary(summary),
    do: %{bytes: summary, max_bytes: byte_size(summary)}

  defp sanitize_summary(_summary), do: %{bytes: "", max_bytes: 0}

  defp normalize_summary_keys(summary) do
    bytes = Map.get(summary, :bytes) || Map.get(summary, "bytes") || ""
    max_bytes = Map.get(summary, :max_bytes) || Map.get(summary, "max_bytes") || byte_size(bytes)
    %{bytes: bytes, max_bytes: max_bytes}
  end

  defp assert_required!(attrs) do
    case Enum.find(@required_fields, &(not present?(attrs, &1))) do
      nil -> :ok
      field -> raise ArgumentError, "missing required evolution field #{field}"
    end
  end

  defp present?(attrs, field),
    do: Map.has_key?(attrs, field) and not is_nil(Map.get(attrs, field))
end

defmodule Chassis.Evolution.Receipts.Store.Memory do
  @moduledoc "Agent-backed in-memory evolution receipt store."

  @type store :: pid() | atom()

  @spec start_link(keyword()) :: Agent.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)

    case name do
      nil -> Agent.start_link(fn -> %{} end, opts)
      name -> start_named(name, opts)
    end
  end

  @spec put(Chassis.Evolution.Receipts.FailureBatchRecord.t()) ::
          {:ok, Chassis.Evolution.Receipts.FailureBatchRecord.t()}
  def put(receipt), do: put(default_store(), receipt)

  @spec put(store(), Chassis.Evolution.Receipts.FailureBatchRecord.t()) ::
          {:ok, Chassis.Evolution.Receipts.FailureBatchRecord.t()}
  def put(store, %Chassis.Evolution.Receipts.FailureBatchRecord{} = receipt) do
    Agent.update(store, &Map.put(&1, receipt.receipt_ref, receipt))
    {:ok, receipt}
  end

  @spec get(store(), String.t()) ::
          {:ok, Chassis.Evolution.Receipts.FailureBatchRecord.t()} | {:error, :not_found}
  def get(store \\ default_store(), receipt_ref) when is_binary(receipt_ref) do
    case Agent.get(store, &Map.fetch(&1, receipt_ref)) do
      {:ok, receipt} -> {:ok, receipt}
      :error -> {:error, :not_found}
    end
  end

  @spec list(store(), keyword()) :: [Chassis.Evolution.Receipts.FailureBatchRecord.t()]
  def list(store \\ default_store(), opts \\ []) do
    source = Keyword.get(opts, :source)

    store
    |> Agent.get(&Map.values/1)
    |> Enum.filter(fn receipt -> is_nil(source) or receipt.source == source end)
    |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
  end

  defp start_named(name, opts) do
    case Agent.start_link(fn -> %{} end, Keyword.put(opts, :name, name)) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      other -> other
    end
  end

  defp default_store do
    case Process.whereis(__MODULE__) do
      nil ->
        {:ok, pid} = start_link()
        pid

      pid ->
        pid
    end
  end
end

defmodule Chassis.Evolution.Receipts.Store.AshPostgres do
  @moduledoc "Future AshPostgres evolution receipt store facade."

  defdelegate put(receipt), to: Chassis.Evolution.Receipts.Store.Memory
  defdelegate put(store, receipt), to: Chassis.Evolution.Receipts.Store.Memory
  defdelegate get(store, receipt_ref), to: Chassis.Evolution.Receipts.Store.Memory
  defdelegate list(store, opts \\ []), to: Chassis.Evolution.Receipts.Store.Memory
end

for name <- [
      CandidatePatchRecord,
      CodingAgentRunRecord,
      TrialRunRecord,
      ScoreMatrixRecord,
      PromotionIntentRecord,
      PromotionRecord,
      SwapRecord,
      EvolutionRollbackRecord,
      OperatorConsentRecord,
      EvolutionStartRecord,
      EvolutionStopRecord
    ] do
  defmodule Module.concat(Chassis.Evolution.Receipts, name) do
    @moduledoc "Future evolution receipt record placeholder for later implementation phases."
    defstruct []

    @type t :: %__MODULE__{}

    @spec put(map()) :: {:error, {:not_implemented, module()}}
    def put(_attrs), do: {:error, {:not_implemented, __MODULE__}}
  end
end
