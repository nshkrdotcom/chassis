defmodule Chassis.Evolution.Refs do
  @moduledoc "Opaque ref string types used across Chassis Evolution."

  @type failure_batch_ref :: String.t()
  @type evidence_ref :: String.t()
  @type candidate_ref :: String.t()
  @type trial_ref :: String.t()
  @type trial_run_ref :: String.t()
  @type score_matrix_ref :: String.t()
  @type promotion_ref :: String.t()
  @type swap_ref :: String.t()
  @type rollback_ref :: String.t()
  @type operator_consent_ref :: String.t()
  @type code_agent_run_ref :: String.t()
  @type stage_artifact_ref :: String.t()
end

defmodule Chassis.Evolution.States do
  @moduledoc "Canonical state set for Chassis Evolution."

  @states [
    :queued,
    :evidence_curated,
    :planning,
    :patching,
    :building,
    :trial_provisioning,
    :trial_running,
    :scoring,
    :blocked,
    :converged,
    :awaiting_authority,
    :awaiting_operator_consent,
    :promotion_requested,
    :promoting,
    :committed,
    :rolled_back,
    :failed,
    :stopped
  ]

  @terminal_states [:committed, :rolled_back, :failed, :stopped]

  @type t ::
          :queued
          | :evidence_curated
          | :planning
          | :patching
          | :building
          | :trial_provisioning
          | :trial_running
          | :scoring
          | :blocked
          | :converged
          | :awaiting_authority
          | :awaiting_operator_consent
          | :promotion_requested
          | :promoting
          | :committed
          | :rolled_back
          | :failed
          | :stopped

  @spec all() :: [t()]
  def all, do: @states

  @spec terminal?(atom()) :: boolean()
  def terminal?(state), do: state in @terminal_states
end

defmodule Chassis.Evolution.PromotionPreconditions do
  @moduledoc "Precondition record required to enter `:promotion_requested`."

  @required_fields [
    :candidate_ref,
    :failure_batch_ref,
    :patch_digest,
    :artifact_digest,
    :score_matrix_ref,
    :regression_gate,
    :authority_ref,
    :operator_consent_ref,
    :rollback_ref,
    :target_installation_ref,
    :approved_state_volume_mounts,
    :trace_id
  ]

  @enforce_keys @required_fields
  defstruct @required_fields

  @type t :: %__MODULE__{
          candidate_ref: Chassis.Evolution.Refs.candidate_ref(),
          failure_batch_ref: Chassis.Evolution.Refs.failure_batch_ref(),
          patch_digest: String.t(),
          artifact_digest: String.t(),
          score_matrix_ref: Chassis.Evolution.Refs.score_matrix_ref(),
          regression_gate: :passed | :blocked,
          authority_ref: String.t(),
          operator_consent_ref: Chassis.Evolution.Refs.operator_consent_ref(),
          rollback_ref: Chassis.Evolution.Refs.rollback_ref(),
          target_installation_ref: String.t(),
          approved_state_volume_mounts: [String.t()],
          trace_id: String.t()
        }

  @spec required_fields() :: [atom()]
  def required_fields, do: @required_fields

  @spec new!(map()) :: t()
  def new!(attrs) when is_map(attrs) do
    Chassis.Evolution.DTO.Helpers.new!(__MODULE__, attrs, @required_fields, @required_fields)
  end
end

defmodule Chassis.Evolution.DTO.Helpers do
  @moduledoc false

  @spec new!(module(), map(), [atom()], [atom()]) :: struct()
  def new!(module, attrs, fields, required_fields) when is_map(attrs) do
    attrs = normalize_keys!(attrs, fields)
    assert_required!(attrs, required_fields)
    struct!(module, attrs)
  end

  @spec to_json(struct()) :: {:ok, String.t()} | {:error, term()}
  def to_json(struct) when is_struct(struct) do
    struct
    |> Map.from_struct()
    |> encode_value()
    |> Jason.encode()
  end

  @spec from_json(module(), String.t(), [atom()], [atom()], keyword()) ::
          {:ok, struct()} | {:error, term()}
  def from_json(module, json, fields, required_fields, opts) when is_binary(json) do
    try do
      with {:ok, decoded} <- decode_json(json),
           {:ok, attrs} <- normalize_keys(decoded, fields),
           {:ok, attrs} <- cast_attrs(attrs, opts) do
        {:ok, new!(module, attrs, fields, required_fields)}
      end
    rescue
      exception in ArgumentError -> {:error, {:invalid_field, Exception.message(exception)}}
    end
  end

  defp decode_json(json) do
    case Jason.decode(json) do
      {:ok, %{} = decoded} -> {:ok, decoded}
      {:ok, _other} -> {:error, :expected_json_object}
      {:error, reason} -> {:error, {:invalid_json, reason}}
    end
  end

  defp normalize_keys(map, fields) when is_map(map) do
    field_by_string = Map.new(fields, &{Atom.to_string(&1), &1})

    Enum.reduce_while(map, {:ok, %{}}, fn {key, value}, {:ok, acc} ->
      case key_to_field(key, field_by_string) do
        {:ok, field} -> {:cont, {:ok, Map.put(acc, field, value)}}
        {:error, field} -> {:halt, {:error, {:unknown_fields, [field]}}}
      end
    end)
  end

  defp normalize_keys!(%{} = attrs, fields) do
    case normalize_keys(attrs, fields) do
      {:ok, normalized} ->
        normalized

      {:error, {:unknown_fields, fields}} ->
        raise ArgumentError, "unknown evolution fields #{inspect(fields)}"
    end
  end

  defp key_to_field(key, field_by_string) when is_atom(key) do
    if key in Map.values(field_by_string), do: {:ok, key}, else: {:error, key}
  end

  defp key_to_field(key, field_by_string) when is_binary(key) do
    case Map.fetch(field_by_string, key) do
      {:ok, field} -> {:ok, field}
      :error -> {:error, String.to_atom(key)}
    end
  end

  defp assert_required!(attrs, required_fields) do
    case Enum.find(required_fields, fn field -> not present?(attrs, field) end) do
      nil -> :ok
      field -> raise ArgumentError, "missing required evolution field #{field}"
    end
  end

  defp present?(attrs, field),
    do: Map.has_key?(attrs, field) and not is_nil(Map.get(attrs, field))

  defp cast_attrs(attrs, opts) do
    attrs =
      attrs
      |> cast_atom_fields(Keyword.get(opts, :atom_fields, []))
      |> cast_datetime_fields(Keyword.get(opts, :datetime_fields, []))
      |> cast_atom_list_fields(Keyword.get(opts, :atom_list_fields, []))
      |> cast_atom_key_map_fields(Keyword.get(opts, :atom_key_map_fields, []))

    {:ok, attrs}
  end

  defp cast_atom_fields(attrs, fields) do
    Enum.reduce(fields, attrs, fn field, acc ->
      Map.update(acc, field, nil, &cast_atom/1)
    end)
  end

  defp cast_datetime_fields(attrs, fields) do
    Enum.reduce(fields, attrs, fn field, acc ->
      Map.update(acc, field, nil, &cast_datetime/1)
    end)
  end

  defp cast_atom_list_fields(attrs, fields) do
    Enum.reduce(fields, attrs, fn field, acc ->
      Map.update(acc, field, nil, fn
        nil -> nil
        list when is_list(list) -> Enum.map(list, &cast_atom/1)
      end)
    end)
  end

  defp cast_atom_key_map_fields(attrs, fields) do
    Enum.reduce(fields, attrs, fn field, acc ->
      Map.update(acc, field, nil, &atomize_map_keys/1)
    end)
  end

  defp cast_atom(nil), do: nil
  defp cast_atom(value) when is_atom(value), do: value
  defp cast_atom(value) when is_binary(value), do: String.to_existing_atom(value)

  defp cast_datetime(nil), do: nil
  defp cast_datetime(%DateTime{} = datetime), do: datetime

  defp cast_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      {:error, reason} -> raise ArgumentError, "invalid datetime #{inspect(reason)}"
    end
  end

  defp atomize_map_keys(nil), do: nil

  defp atomize_map_keys(map) when is_map(map) do
    Map.new(map, fn
      {key, value} when is_atom(key) -> {key, value}
      {key, value} when is_binary(key) -> {String.to_existing_atom(key), value}
    end)
  end

  defp encode_value(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
  defp encode_value(value) when is_boolean(value), do: value
  defp encode_value(atom) when is_atom(atom) and not is_nil(atom), do: Atom.to_string(atom)
  defp encode_value(list) when is_list(list), do: Enum.map(list, &encode_value/1)

  defp encode_value(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {key, encode_value(value)} end)
  end

  defp encode_value(value), do: value
end

for {name, fields, required_fields, opts} <- [
      {FailureBatch,
       [
         :failure_batch_ref,
         :tenant_ref,
         :installation_ref,
         :evidence_refs,
         :summary,
         :redaction_posture,
         :flagged_by_ref,
         :batch_hint_ref,
         :created_at
       ],
       [
         :failure_batch_ref,
         :tenant_ref,
         :installation_ref,
         :evidence_refs,
         :summary,
         :redaction_posture,
         :created_at
       ],
       atom_fields: [:redaction_posture],
       datetime_fields: [:created_at],
       atom_key_map_fields: [:summary]},
      {CandidatePatch,
       [
         :candidate_ref,
         :base_release_ref,
         :base_image_digest,
         :patch_digest,
         :diff_ref,
         :failure_batch_ref,
         :code_agent_run_ref,
         :prompt_summary_ref,
         :created_at
       ], [:candidate_ref, :base_release_ref, :patch_digest, :diff_ref],
       datetime_fields: [:created_at]},
      {CandidateImage,
       [:candidate_ref, :artifact_kind, :digest, :built_at, :build_log_ref, :builder_ref],
       [:candidate_ref, :artifact_kind, :digest, :built_at],
       atom_fields: [:artifact_kind], datetime_fields: [:built_at]},
      {TrialRun,
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
       ], [:trial_run_ref, :trial_ref, :candidate_ref, :started_at],
       atom_fields: [:verdict], datetime_fields: [:started_at, :completed_at]},
      {ScoreMatrix,
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
       ],
       [
         :score_matrix_ref,
         :candidate_ref,
         :baseline_score,
         :candidate_score,
         :regression_gate,
         :confidence
       ], atom_fields: [:regression_gate, :scorer_kind], atom_list_fields: [:blocked_reasons]},
      {PromotionIntent,
       [
         :promotion_ref,
         :candidate_ref,
         :target_installation_ref,
         :issued_at,
         :consent_required?,
         :consent_ref_template
       ], [:promotion_ref, :candidate_ref, :target_installation_ref, :issued_at],
       datetime_fields: [:issued_at]},
      {PromotionReceipt,
       [:promotion_ref, :swap_ref, :outcome, :committed_at_or_rolled_back_at, :rollback_ref],
       [:promotion_ref, :swap_ref, :outcome, :committed_at_or_rolled_back_at],
       atom_fields: [:outcome], datetime_fields: [:committed_at_or_rolled_back_at]},
      {RollbackReceipt,
       [:rollback_ref, :swap_ref, :restored_artifact_digest, :reason_code, :rolled_back_at],
       [:rollback_ref, :swap_ref, :restored_artifact_digest, :rolled_back_at],
       atom_fields: [:reason_code], datetime_fields: [:rolled_back_at]},
      {OperatorConsent,
       [
         :operator_consent_ref,
         :candidate_ref,
         :decision,
         :recorded_at,
         :actor_ref,
         :justification_summary,
         :lower_read_lease_ref
       ], [:operator_consent_ref, :candidate_ref, :decision, :recorded_at, :actor_ref],
       atom_fields: [:decision], datetime_fields: [:recorded_at]},
      {CodeAgentRun,
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
       ], [:code_agent_run_ref, :runner_kind, :candidate_ref, :started_at],
       atom_fields: [:runner_kind, :exit_status], datetime_fields: [:started_at, :completed_at]},
      {StageArtifact, [:stage_artifact_ref, :kind, :digest, :bytes, :stored_at_ref],
       [:stage_artifact_ref, :kind, :digest, :bytes], atom_fields: [:kind]}
    ] do
  defmodule Module.concat(Chassis.Evolution.DTO, name) do
    @moduledoc "Evolution DTO contract."
    @fields fields
    @required_fields required_fields
    @json_opts opts
    @enforce_keys @required_fields
    defstruct @fields

    @type t :: %__MODULE__{}

    @spec fields() :: [atom()]
    def fields, do: @fields

    @spec required_fields() :: [atom()]
    def required_fields, do: @required_fields

    @spec new!(map()) :: t()
    def new!(attrs) when is_map(attrs) do
      Chassis.Evolution.DTO.Helpers.new!(__MODULE__, attrs, @fields, @required_fields)
    end

    @spec to_json(t()) :: {:ok, String.t()} | {:error, term()}
    def to_json(%__MODULE__{} = dto), do: Chassis.Evolution.DTO.Helpers.to_json(dto)

    @spec from_json(String.t()) :: {:ok, t()} | {:error, term()}
    def from_json(json) when is_binary(json) do
      Chassis.Evolution.DTO.Helpers.from_json(
        __MODULE__,
        json,
        @fields,
        @required_fields,
        @json_opts
      )
    end
  end
end

defmodule Chassis.Evolution.CodingAgentRunner do
  @moduledoc "Behaviour for provider-agnostic external coding-agent CLIs."

  alias Chassis.Evolution.DTO.{CodeAgentRun, FailureBatch}

  @type opts :: keyword()
  @type spawn_request :: %{
          required(:tenant_ref) => String.t(),
          required(:installation_ref) => String.t(),
          required(:failure_batch) => FailureBatch.t(),
          required(:base_release_ref) => String.t(),
          optional(:budget_ref) => String.t(),
          optional(:runner_profile_ref) => String.t()
        }

  @callback spawn_run(spawn_request(), opts()) :: {:ok, CodeAgentRun.t()} | {:error, term()}
  @callback cancel_run(Chassis.Evolution.Refs.code_agent_run_ref(), opts()) ::
              :ok | {:error, term()}
end

defmodule Chassis.Evolution.Scorer do
  @moduledoc "Behaviour for replay-based candidate scoring."

  alias Chassis.Evolution.DTO.{ScoreMatrix, TrialRun}

  @type opts :: keyword()

  @callback score_trial(TrialRun.t(), opts()) :: {:ok, ScoreMatrix.t()} | {:error, term()}
end

defmodule Chassis.Evolution.TrialProvider do
  @moduledoc "Behaviour for trial worker provisioning."

  @type kind :: :fixture | :container | :systemd | :ssh
  @type opts :: keyword()

  @callback provision_trial(
              kind(),
              Chassis.Evolution.DTO.CandidatePatch.t() | Chassis.Evolution.DTO.CandidateImage.t(),
              opts()
            ) ::
              {:ok, %{trial_ref: String.t(), trial_node_ref: String.t()}} | {:error, term()}

  @callback teardown_trial(String.t(), opts()) :: :ok | {:error, term()}
end

defmodule Chassis.Evolution.PromotionExecutor do
  @moduledoc "Behaviour the Host Daemon implements for swap execution."

  alias Chassis.Evolution.PromotionPreconditions

  @type opts :: keyword()

  @callback execute_swap(PromotionPreconditions.t(), opts()) ::
              {:ok, %{swap_ref: String.t(), health_probe_window_ms: pos_integer()}}
              | {:error, term()}

  @callback rollback_swap(String.t(), opts()) ::
              {:ok, %{rollback_ref: String.t(), restored_artifact_digest: String.t()}}
              | {:error, term()}
end
