defmodule Chassis.Evolution.Receipts.RecordHelpers do
  @moduledoc false

  @sensitive_keys [
    :raw_transcript,
    :raw_body,
    :raw_bytes,
    :raw_provider_token,
    :provider_token,
    :raw_prompt,
    :raw_diff,
    :transcript,
    :body,
    :payload
  ]

  @spec new!(module(), map(), [atom()], [atom()], atom(), atom()) :: struct()
  def new!(module, attrs, fields, required_fields, receipt_kind, ref_field) when is_map(attrs) do
    attrs =
      attrs
      |> normalize_allowed_fields(fields)
      |> Map.put_new(:receipt_kind, receipt_kind)
      |> Map.put_new(:receipt_ref, receipt_ref(receipt_kind, ref_field, attrs))
      |> Map.put_new(:inserted_at, DateTime.utc_now())
      |> Map.update(:summary, nil, &sanitize_summary/1)

    assert_required!(attrs, required_fields)
    struct!(module, attrs)
  end

  @spec sanitize_summary(term()) :: map()
  def sanitize_summary(%{} = summary) do
    bytes = Map.get(summary, :bytes) || Map.get(summary, "bytes") || ""
    max_bytes = Map.get(summary, :max_bytes) || Map.get(summary, "max_bytes") || byte_size(bytes)
    %{bytes: bytes, max_bytes: max_bytes}
  end

  def sanitize_summary(summary) when is_binary(summary),
    do: %{bytes: summary, max_bytes: byte_size(summary)}

  def sanitize_summary(_summary), do: %{bytes: "", max_bytes: 0}

  @spec normalize_allowed_fields(map(), [atom()]) :: map()
  def normalize_allowed_fields(attrs, fields) do
    string_fields = Map.new(fields, &{Atom.to_string(&1), &1})

    attrs
    |> Enum.reject(fn {key, _value} -> sensitive_key?(key) end)
    |> Map.new(fn
      {key, value} when is_binary(key) -> {Map.get(string_fields, key, key), value}
      {key, value} -> {key, value}
    end)
    |> Map.take(fields)
  end

  @spec assert_required!(map(), [atom()]) :: :ok
  def assert_required!(attrs, required_fields) do
    case Enum.find(required_fields, &(not present?(attrs, &1))) do
      nil -> :ok
      field -> raise ArgumentError, "missing required evolution field #{field}"
    end
  end

  @spec receipt_ref(atom(), atom(), map()) :: String.t()
  def receipt_ref(receipt_kind, ref_field, attrs) do
    explicit = Map.get(attrs, :receipt_ref) || Map.get(attrs, "receipt_ref")
    ref_value = Map.get(attrs, ref_field) || Map.get(attrs, Atom.to_string(ref_field))
    explicit || "receipt:#{receipt_kind}:#{ref_value}"
  end

  defp sensitive_key?(key) when is_atom(key), do: key in @sensitive_keys
  defp sensitive_key?(key) when is_binary(key), do: String.to_atom(key) in @sensitive_keys

  defp present?(attrs, field),
    do: Map.has_key?(attrs, field) and not is_nil(Map.get(attrs, field))
end

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
    :receipt_kind,
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

  defstruct @fields

  @type t :: %__MODULE__{}

  @spec fields() :: [atom()]
  def fields, do: @fields

  @spec required_fields() :: [atom()]
  def required_fields, do: @required_fields

  @spec new!(map()) :: t()
  def new!(attrs) when is_map(attrs) do
    attrs =
      Chassis.Evolution.Receipts.RecordHelpers.normalize_allowed_fields(attrs, @fields)
      |> Map.put_new(:receipt_kind, :failure_batch)
      |> Map.put_new(
        :receipt_ref,
        Chassis.Evolution.Receipts.RecordHelpers.receipt_ref(
          :failure_batch,
          :failure_batch_ref,
          attrs
        )
      )
      |> Map.put_new(:inserted_at, DateTime.utc_now())
      |> Map.put(
        :summary,
        Chassis.Evolution.Receipts.RecordHelpers.sanitize_summary(Map.get(attrs, :summary))
      )
      |> Map.update(:evidence_refs, [], &List.wrap/1)

    Chassis.Evolution.Receipts.RecordHelpers.assert_required!(attrs, @required_fields)
    struct!(__MODULE__, attrs)
  end
end

for {name, receipt_kind, ref_field, fields, required_fields} <- [
      {CandidatePatchRecord, :candidate_patch, :candidate_ref,
       [
         :candidate_ref,
         :base_release_ref,
         :base_image_digest,
         :patch_digest,
         :diff_ref,
         :failure_batch_ref,
         :code_agent_run_ref,
         :prompt_summary_ref
       ], [:candidate_ref, :base_release_ref, :patch_digest, :diff_ref]},
      {CodingAgentRunRecord, :coding_agent_run, :code_agent_run_ref,
       [
         :code_agent_run_ref,
         :runner_kind,
         :candidate_ref,
         :failure_batch_ref,
         :started_at,
         :completed_at,
         :exit_status,
         :prompt_summary_ref,
         :diff_ref,
         :cost_ref,
         :token_ref,
         :log_ref
       ], [:code_agent_run_ref, :runner_kind, :candidate_ref, :started_at]},
      {TrialRunRecord, :trial_run, :trial_run_ref,
       [
         :trial_run_ref,
         :trial_ref,
         :candidate_ref,
         :failure_batch_ref,
         :baseline_set_ref,
         :started_at,
         :completed_at,
         :verdict,
         :replay_log_ref
       ], [:trial_run_ref, :trial_ref, :candidate_ref, :started_at]},
      {ScoreMatrixRecord, :score_matrix, :score_matrix_ref,
       [
         :score_matrix_ref,
         :candidate_ref,
         :baseline_score,
         :candidate_score,
         :regression_gate,
         :confidence,
         :blocked_reasons,
         :scorer_receipts,
         :scorer_kind
       ], [:score_matrix_ref, :candidate_ref, :regression_gate, :confidence]},
      {PromotionIntentRecord, :promotion_intent, :promotion_ref,
       [
         :promotion_ref,
         :candidate_ref,
         :target_installation_ref,
         :issued_at,
         :consent_required?,
         :consent_ref_template
       ], [:promotion_ref, :candidate_ref, :target_installation_ref, :issued_at]},
      {PromotionRecord, :promotion, :promotion_ref,
       [:promotion_ref, :swap_ref, :outcome, :committed_at_or_rolled_back_at, :rollback_ref],
       [:promotion_ref, :swap_ref, :outcome, :committed_at_or_rolled_back_at]},
      {SwapRecord, :swap, :swap_ref,
       [
         :swap_ref,
         :candidate_ref,
         :target_installation_ref,
         :artifact_digest,
         :previous_artifact_digest,
         :health_probe_window_ms,
         :swapped_at
       ], [:swap_ref, :candidate_ref, :target_installation_ref, :artifact_digest]},
      {EvolutionRollbackRecord, :evolution_rollback, :rollback_ref,
       [:rollback_ref, :swap_ref, :restored_artifact_digest, :reason_code, :rolled_back_at],
       [:rollback_ref, :swap_ref, :restored_artifact_digest, :rolled_back_at]},
      {OperatorConsentRecord, :operator_consent, :operator_consent_ref,
       [
         :operator_consent_ref,
         :candidate_ref,
         :decision,
         :recorded_at,
         :actor_ref,
         :justification_summary,
         :lower_read_lease_ref
       ], [:operator_consent_ref, :candidate_ref, :decision, :recorded_at, :actor_ref]},
      {EvolutionStartRecord, :evolution_start, :evolution_run_ref,
       [:evolution_run_ref, :failure_batch_ref, :started_at, :actor_ref],
       [:evolution_run_ref, :failure_batch_ref, :started_at]},
      {EvolutionStopRecord, :evolution_stop, :evolution_run_ref,
       [:evolution_run_ref, :stopped_at, :reason_code, :actor_ref],
       [:evolution_run_ref, :stopped_at, :reason_code]}
    ] do
  defmodule Module.concat(Chassis.Evolution.Receipts, name) do
    @moduledoc "Evolution lifecycle receipt record."
    @receipt_kind receipt_kind
    @ref_field ref_field
    @specific_fields fields
    @fields [
              :receipt_ref,
              :tenant_ref,
              :installation_ref,
              :trace_id,
              :summary,
              :receipt_kind,
              :inserted_at
            ] ++ @specific_fields
    @required_fields [:tenant_ref, :installation_ref, :trace_id] ++ required_fields

    defstruct @fields

    @type t :: %__MODULE__{}

    @spec fields() :: [atom()]
    def fields, do: @fields

    @spec required_fields() :: [atom()]
    def required_fields, do: @required_fields

    @spec receipt_kind() :: atom()
    def receipt_kind, do: @receipt_kind

    @spec new!(map()) :: t()
    def new!(attrs) when is_map(attrs) do
      Chassis.Evolution.Receipts.RecordHelpers.new!(
        __MODULE__,
        attrs,
        @fields,
        @required_fields,
        @receipt_kind,
        @ref_field
      )
    end

    @spec put(map() | t(), keyword()) :: {:ok, t()} | {:error, term()}
    def put(attrs_or_record, opts \\ [])

    def put(%__MODULE__{} = record, opts) do
      case Keyword.fetch(opts, :store) do
        {:ok, store} -> Chassis.Evolution.Receipts.Store.Memory.put(store, record)
        :error -> Chassis.Evolution.Receipts.Store.Memory.put(record)
      end
    end

    def put(attrs, opts) when is_map(attrs), do: attrs |> new!() |> put(opts)
  end
end

defmodule Chassis.Evolution.Consent do
  @moduledoc """
  Operator-consent helper for evolution promotion authority binding.

  This module owns the receipt-side validation used before Citadel promotion
  authority is compiled. It deliberately stores only bounded summaries and refs.
  """

  alias Chassis.Evolution.Receipts.OperatorConsentRecord
  alias Chassis.Evolution.Receipts.Store.Memory

  @default_ttl_seconds 3600
  @approved_decisions [:approve, :approved]

  @type validation :: %{
          operator_consent_ref: String.t(),
          candidate_ref: String.t(),
          recorded_at: DateTime.t(),
          actor_ref: String.t()
        }

  @spec record_operator_consent(String.t(), String.t(), atom(), map(), keyword()) ::
          {:ok, OperatorConsentRecord.t()} | {:error, term()}
  def record_operator_consent(candidate_ref, actor_ref, decision, attrs, opts \\ [])
      when is_binary(candidate_ref) and is_binary(actor_ref) and is_map(attrs) do
    attrs =
      attrs
      |> Map.new()
      |> Map.merge(%{
        candidate_ref: candidate_ref,
        actor_ref: actor_ref,
        decision: decision
      })
      |> Map.put_new(:recorded_at, DateTime.utc_now())

    with :ok <- validate_actor(actor_ref),
         :ok <- validate_recordable_decision(decision) do
      record = OperatorConsentRecord.new!(attrs)

      case Keyword.fetch(opts, :store) do
        {:ok, store} -> Memory.put(store, record)
        :error -> {:ok, record}
      end
    end
  rescue
    exception in ArgumentError -> {:error, {:invalid_consent, Exception.message(exception)}}
  end

  @spec validate(map() | struct(), keyword()) :: {:ok, validation()} | {:error, atom()}
  def validate(consent, opts \\ [])

  def validate(consent, opts) when is_map(consent) do
    attrs = attrs(consent)

    with :ok <- require_present(attrs, :operator_consent_ref),
         :ok <- require_present(attrs, :candidate_ref),
         :ok <- require_present(attrs, :recorded_at),
         :ok <- require_present(attrs, :actor_ref),
         :ok <- validate_expected_ref(attrs, opts),
         :ok <- validate_expected_candidate(attrs, opts),
         :ok <- validate_actor(Map.get(attrs, :actor_ref)),
         :ok <- validate_approved(Map.get(attrs, :decision)),
         :ok <- validate_ttl(Map.get(attrs, :recorded_at), opts) do
      {:ok,
       %{
         operator_consent_ref: Map.fetch!(attrs, :operator_consent_ref),
         candidate_ref: Map.fetch!(attrs, :candidate_ref),
         recorded_at: Map.fetch!(attrs, :recorded_at),
         actor_ref: Map.fetch!(attrs, :actor_ref)
       }}
    end
  end

  def validate(_other, _opts), do: {:error, :invalid_record}

  defp attrs(%_struct{} = consent), do: Map.from_struct(consent)
  defp attrs(consent), do: Map.new(consent)

  defp require_present(attrs, field) do
    case Map.get(attrs, field) || Map.get(attrs, Atom.to_string(field)) do
      value when is_binary(value) and value != "" -> :ok
      %DateTime{} -> :ok
      value when is_atom(value) and not is_nil(value) -> :ok
      _other -> {:error, field}
    end
  end

  defp validate_expected_ref(attrs, opts) do
    case Keyword.get(opts, :operator_consent_ref) do
      nil ->
        :ok

      expected ->
        validate_expected_value(
          expected,
          Map.get(attrs, :operator_consent_ref),
          :operator_consent_mismatch
        )
    end
  end

  defp validate_expected_candidate(attrs, opts) do
    case Keyword.get(opts, :candidate_ref) do
      nil ->
        :ok

      expected ->
        validate_expected_value(expected, Map.get(attrs, :candidate_ref), :candidate_mismatch)
    end
  end

  defp validate_expected_value(expected, actual, _reason) when expected == actual, do: :ok
  defp validate_expected_value(_expected, _actual, reason), do: {:error, reason}

  defp validate_actor(actor_ref) when is_binary(actor_ref) do
    if String.starts_with?(actor_ref, ["user:", "operator:"]) do
      :ok
    else
      {:error, :actor_not_user}
    end
  end

  defp validate_actor(_other), do: {:error, :actor_not_user}

  defp validate_recordable_decision(decision) when decision in [:approve, :reject], do: :ok
  defp validate_recordable_decision(:approved), do: :ok
  defp validate_recordable_decision(_decision), do: {:error, :invalid_decision}

  defp validate_approved(decision) when decision in @approved_decisions, do: :ok
  defp validate_approved(_decision), do: {:error, :not_approved}

  defp validate_ttl(%DateTime{} = recorded_at, opts) do
    now = Keyword.get(opts, :now, DateTime.utc_now())
    ttl_seconds = Keyword.get(opts, :ttl_seconds, @default_ttl_seconds)

    case DateTime.diff(now, recorded_at, :second) do
      age when age <= ttl_seconds -> :ok
      _expired -> {:error, :expired}
    end
  end

  defp validate_ttl(_recorded_at, _opts), do: {:error, :invalid_recorded_at}
end

defmodule Chassis.Evolution.Receipts.AfterActions.Recorder do
  @moduledoc "In-memory after-action event recorder for receipt side effects."

  @spec start_link(keyword()) :: Agent.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)

    case name do
      nil -> Agent.start_link(fn -> [] end, opts)
      name -> Agent.start_link(fn -> [] end, Keyword.put(opts, :name, name))
    end
  end

  @spec record(pid() | atom(), map()) :: :ok
  def record(recorder, event), do: Agent.update(recorder, &[event | &1])

  @spec list(pid() | atom()) :: [map()]
  def list(recorder), do: Agent.get(recorder, &Enum.reverse/1)
end

defmodule Chassis.Evolution.Receipts.AfterActions do
  @moduledoc "Receipt after-action stubs for AITrace, Observability, Mezzanine, and AppKit."

  alias Chassis.Evolution.Receipts.AfterActions.Recorder

  @sensitive_keys MapSet.new([
                    :raw_transcript,
                    :raw_body,
                    :raw_bytes,
                    :raw_provider_token,
                    :provider_token,
                    :raw_prompt,
                    :raw_diff,
                    :transcript,
                    :body,
                    :payload
                  ])

  @spec stub_callbacks(pid() | atom()) :: [(struct() -> :ok)]
  def stub_callbacks(recorder) do
    [
      &record_surface(recorder, :aitrace, &1),
      &record_surface(recorder, :observability, &1),
      &record_surface(recorder, :mezzanine_outbox, &1),
      &record_surface(recorder, :appkit_projection, &1)
    ]
  end

  @spec projection_hook((map() -> :ok | {:ok, term()} | {:error, term()})) ::
          (struct() -> :ok | {:error, term()})
  def projection_hook(publisher) when is_function(publisher, 1) do
    fn record ->
      record
      |> projection_event()
      |> publisher.()
      |> normalize_callback_result()
    end
  end

  @spec projection_event(struct()) :: map()
  def projection_event(record) when is_map(record) do
    payload = safe_payload(record)

    %{
      projection: projection_for(record),
      primary_ref: primary_ref(record, payload),
      payload: payload,
      trace_id: Map.get(payload, :trace_id),
      tenant_ref: Map.get(payload, :tenant_ref),
      installation_ref: Map.get(payload, :installation_ref),
      correlation_id: Map.get(payload, :receipt_ref),
      idempotency_key: Map.get(payload, :receipt_ref)
    }
  end

  defp record_surface(recorder, surface, record) do
    Recorder.record(recorder, %{
      surface: surface,
      receipt_ref: record.receipt_ref,
      receipt_kind: Map.get(record, :receipt_kind),
      tenant_ref: Map.get(record, :tenant_ref),
      candidate_ref: Map.get(record, :candidate_ref),
      trace_id: Map.get(record, :trace_id)
    })
  end

  defp normalize_callback_result(:ok), do: :ok
  defp normalize_callback_result({:ok, _value}), do: :ok
  defp normalize_callback_result({:error, reason}), do: {:error, reason}
  defp normalize_callback_result(other), do: {:error, {:invalid_after_action_result, other}}

  defp projection_for(%Chassis.Evolution.Receipts.FailureBatchRecord{}), do: :chassis_evolution
  defp projection_for(%Chassis.Evolution.Receipts.EvolutionStartRecord{}), do: :chassis_evolution
  defp projection_for(%Chassis.Evolution.Receipts.EvolutionStopRecord{}), do: :chassis_evolution
  defp projection_for(%Chassis.Evolution.Receipts.CandidatePatchRecord{}), do: :chassis_candidate
  defp projection_for(%Chassis.Evolution.Receipts.CodingAgentRunRecord{}), do: :chassis_candidate
  defp projection_for(%Chassis.Evolution.Receipts.TrialRunRecord{}), do: :chassis_trial
  defp projection_for(%Chassis.Evolution.Receipts.ScoreMatrixRecord{}), do: :chassis_score_matrix
  defp projection_for(%Chassis.Evolution.Receipts.PromotionIntentRecord{}), do: :chassis_promotion
  defp projection_for(%Chassis.Evolution.Receipts.PromotionRecord{}), do: :chassis_promotion
  defp projection_for(%Chassis.Evolution.Receipts.OperatorConsentRecord{}), do: :chassis_promotion
  defp projection_for(%Chassis.Evolution.Receipts.SwapRecord{}), do: :chassis_swap
  defp projection_for(%Chassis.Evolution.Receipts.EvolutionRollbackRecord{}), do: :chassis_swap
  defp projection_for(_record), do: :chassis_evolution

  defp primary_ref(%Chassis.Evolution.Receipts.ScoreMatrixRecord{}, payload),
    do: Map.get(payload, :score_matrix_ref)

  defp primary_ref(%Chassis.Evolution.Receipts.TrialRunRecord{}, payload),
    do: Map.get(payload, :trial_ref) || Map.get(payload, :trial_run_ref)

  defp primary_ref(%Chassis.Evolution.Receipts.PromotionIntentRecord{}, payload),
    do: Map.get(payload, :promotion_ref)

  defp primary_ref(%Chassis.Evolution.Receipts.PromotionRecord{}, payload),
    do: Map.get(payload, :promotion_ref)

  defp primary_ref(%Chassis.Evolution.Receipts.OperatorConsentRecord{}, payload),
    do: Map.get(payload, :operator_consent_ref)

  defp primary_ref(%Chassis.Evolution.Receipts.SwapRecord{}, payload),
    do: Map.get(payload, :swap_ref)

  defp primary_ref(%Chassis.Evolution.Receipts.EvolutionRollbackRecord{}, payload),
    do: Map.get(payload, :rollback_ref)

  defp primary_ref(%Chassis.Evolution.Receipts.EvolutionStartRecord{}, payload),
    do: Map.get(payload, :evolution_run_ref)

  defp primary_ref(%Chassis.Evolution.Receipts.EvolutionStopRecord{}, payload),
    do: Map.get(payload, :evolution_run_ref)

  defp primary_ref(_record, payload) do
    Enum.find_value(
      [
        :failure_batch_ref,
        :candidate_ref,
        :trial_ref,
        :trial_run_ref,
        :score_matrix_ref,
        :promotion_ref,
        :operator_consent_ref,
        :swap_ref,
        :rollback_ref,
        :evolution_run_ref,
        :receipt_ref
      ],
      fn key ->
        case Map.get(payload, key) do
          value when is_binary(value) and value != "" -> value
          _missing -> nil
        end
      end
    )
  end

  defp safe_payload(%_struct{} = record), do: record |> Map.from_struct() |> safe_payload()

  defp safe_payload(map) when is_map(map) do
    map
    |> Enum.reject(fn {key, _value} -> sensitive_key?(key) end)
    |> Map.new(fn {key, value} -> {key, safe_value(value)} end)
  end

  defp safe_value(%DateTime{} = value), do: value
  defp safe_value(value) when is_map(value), do: safe_payload(value)
  defp safe_value(value) when is_list(value), do: Enum.map(value, &safe_value/1)
  defp safe_value(value), do: value

  defp sensitive_key?(key) when is_atom(key), do: MapSet.member?(@sensitive_keys, key)

  defp sensitive_key?(key) when is_binary(key) do
    key
    |> String.to_existing_atom()
    |> sensitive_key?()
  rescue
    ArgumentError -> false
  end
end

defmodule Chassis.Evolution.Receipts.Store.Memory do
  @moduledoc "Agent-backed in-memory evolution receipt store."

  @type store :: pid() | atom()
  @known_records [
    Chassis.Evolution.Receipts.FailureBatchRecord,
    Chassis.Evolution.Receipts.CandidatePatchRecord,
    Chassis.Evolution.Receipts.CodingAgentRunRecord,
    Chassis.Evolution.Receipts.TrialRunRecord,
    Chassis.Evolution.Receipts.ScoreMatrixRecord,
    Chassis.Evolution.Receipts.PromotionIntentRecord,
    Chassis.Evolution.Receipts.PromotionRecord,
    Chassis.Evolution.Receipts.SwapRecord,
    Chassis.Evolution.Receipts.EvolutionRollbackRecord,
    Chassis.Evolution.Receipts.OperatorConsentRecord,
    Chassis.Evolution.Receipts.EvolutionStartRecord,
    Chassis.Evolution.Receipts.EvolutionStopRecord
  ]

  @spec known_records() :: [module()]
  def known_records, do: @known_records

  @spec start_link(keyword()) :: Agent.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    state = %{records: %{}, after_actions: Keyword.get(opts, :after_actions, [])}

    case name do
      nil -> Agent.start_link(fn -> state end)
      name -> start_named(name, state)
    end
  end

  @spec put(struct()) :: {:ok, struct()} | {:error, term()}
  def put(receipt), do: put(default_store(), receipt)

  @spec put(store(), struct()) :: {:ok, struct()} | {:error, term()}
  def put(store, %module{} = receipt) when module in @known_records do
    Agent.update(store, fn state ->
      update_in(state.records, &Map.put(&1, receipt.receipt_ref, receipt))
    end)

    run_after_actions(store, receipt)
    {:ok, receipt}
  end

  def put(_store, other), do: {:error, {:invalid_record, other}}

  @spec get(store(), String.t()) :: {:ok, struct()} | {:error, :not_found}
  def get(store \\ default_store(), receipt_ref) when is_binary(receipt_ref) do
    case Agent.get(store, &Map.fetch(&1.records, receipt_ref)) do
      {:ok, receipt} -> {:ok, receipt}
      :error -> {:error, :not_found}
    end
  end

  @spec list(store(), keyword()) :: [struct()]
  def list(store \\ default_store(), opts \\ []) do
    kind = Keyword.get(opts, :kind)

    store
    |> Agent.get(&Map.values(&1.records))
    |> Enum.filter(fn receipt -> is_nil(kind) or receipt.__struct__ == kind end)
    |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
  end

  defp start_named(name, state) do
    case Agent.start_link(fn -> state end, name: name) do
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

  defp run_after_actions(store, receipt) do
    callbacks = Agent.get(store, & &1.after_actions)

    Enum.each(callbacks, fn callback ->
      try do
        callback.(receipt)
      rescue
        exception ->
          require Logger
          Logger.warning("evolution receipt after_action raised: #{Exception.message(exception)}")
      end
    end)
  end
end

defmodule Chassis.Evolution.Receipts.Store.AshPostgres do
  @moduledoc """
  AshPostgres-compatible receipt store facade.

  Phase 24 keeps this in-process but routes through the same contract as the
  memory store so lifecycle receipts can assert backend parity before a real
  database resource is introduced.
  """

  defdelegate start_link(opts \\ []), to: Chassis.Evolution.Receipts.Store.Memory
  defdelegate put(receipt), to: Chassis.Evolution.Receipts.Store.Memory
  defdelegate put(store, receipt), to: Chassis.Evolution.Receipts.Store.Memory
  defdelegate get(store, receipt_ref), to: Chassis.Evolution.Receipts.Store.Memory
  defdelegate list(store, opts \\ []), to: Chassis.Evolution.Receipts.Store.Memory
end
