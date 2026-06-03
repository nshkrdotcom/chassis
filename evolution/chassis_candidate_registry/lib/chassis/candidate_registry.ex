defmodule Chassis.Candidate.Registry.Entry do
  @moduledoc "Candidate registry entry."

  @fields [
    :candidate_ref,
    :tenant_ref,
    :installation_ref,
    :base_release_ref,
    :base_image_digest,
    :patch_digest,
    :candidate_image_digest,
    :release_digest,
    :failure_batch_ref,
    :score_matrix_ref,
    :authority_ref,
    :promotion_receipt_ref,
    :rollback_ref,
    :operator_consent_ref,
    :trace_id,
    :created_at,
    :updated_at,
    :last_state
  ]

  @required_fields [
    :candidate_ref,
    :tenant_ref,
    :base_release_ref,
    :patch_digest,
    :failure_batch_ref,
    :trace_id,
    :last_state
  ]

  @sensitive_keys [:raw_prompt, :raw_diff, :raw_provider_token, :provider_token, :prompt, :diff]

  defstruct @fields

  @type t :: %__MODULE__{}

  @spec fields() :: [atom()]
  def fields, do: @fields

  @spec required_fields() :: [atom()]
  def required_fields, do: @required_fields

  @spec ash_resource_schema() :: map()
  def ash_resource_schema do
    %{
      resource: __MODULE__,
      primary_key: :candidate_ref,
      fields: Map.new(@fields, &{&1, :field}),
      after_action_pattern: "Mezzanine.Execution.ExecutionRecord"
    }
  end

  @spec new!(map()) :: t()
  def new!(attrs) when is_map(attrs) do
    attrs =
      attrs
      |> normalize_keys()
      |> Map.drop(@sensitive_keys)
      |> Map.take(@fields)
      |> Map.put_new(:last_state, :patching)
      |> Map.put_new(:created_at, DateTime.utc_now())
      |> Map.put_new(:updated_at, DateTime.utc_now())
      |> validate_state!()

    assert_required!(attrs)
    struct!(__MODULE__, attrs)
  end

  defp normalize_keys(attrs) do
    string_fields = Map.new(@fields ++ @sensitive_keys, &{Atom.to_string(&1), &1})

    Map.new(attrs, fn
      {key, value} when is_binary(key) -> {Map.get(string_fields, key, key), value}
      {key, value} -> {key, value}
    end)
  end

  defp validate_state!(%{last_state: state} = attrs) when is_binary(state) do
    Map.put(attrs, :last_state, String.to_existing_atom(state))
    |> validate_state!()
  end

  defp validate_state!(%{last_state: state} = attrs) do
    if state in Chassis.Evolution.States.all() do
      attrs
    else
      raise ArgumentError, "invalid candidate lifecycle state #{inspect(state)}"
    end
  end

  defp assert_required!(attrs) do
    case Enum.find(@required_fields, &(not present?(attrs, &1))) do
      nil -> :ok
      field -> raise ArgumentError, "missing required candidate field #{field}"
    end
  end

  defp present?(attrs, field),
    do: Map.has_key?(attrs, field) and not is_nil(Map.get(attrs, field))
end

defmodule Chassis.Candidate.Registry.Store.Memory do
  @moduledoc "Agent-backed candidate registry store."

  alias Chassis.Candidate.Registry.Entry

  @type store :: pid() | atom()

  @spec start_link(keyword()) :: Agent.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)

    case name do
      nil -> Agent.start_link(fn -> %{} end, opts)
      name -> start_named(name, opts)
    end
  end

  @spec put(Entry.t()) :: {:ok, Entry.t()}
  def put(entry), do: put(default_store(), entry)

  @spec put(store(), Entry.t()) :: {:ok, Entry.t()}
  def put(store, %Entry{} = entry) do
    Agent.update(store, &Map.put(&1, entry.candidate_ref, entry))
    {:ok, entry}
  end

  @spec get(store(), String.t()) :: {:ok, Entry.t()} | {:error, :not_found}
  def get(store, candidate_ref) when is_binary(candidate_ref) do
    case Agent.get(store, &Map.fetch(&1, candidate_ref)) do
      {:ok, entry} -> {:ok, entry}
      :error -> {:error, :not_found}
    end
  end

  @spec list(store(), keyword()) :: [Entry.t()]
  def list(store, opts \\ []) do
    tenant_ref = Keyword.get(opts, :tenant_ref)

    store
    |> Agent.get(&Map.values/1)
    |> Enum.filter(fn entry -> is_nil(tenant_ref) or entry.tenant_ref == tenant_ref end)
    |> Enum.sort_by(& &1.updated_at, {:desc, DateTime})
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

defmodule Chassis.Candidate.Registry.Store.AshPostgres do
  @moduledoc """
  AshPostgres-compatible candidate registry facade.

  Phase 24 keeps this in-process while asserting the same entry schema and
  store contract as the memory backend.
  """

  defdelegate start_link(opts \\ []), to: Chassis.Candidate.Registry.Store.Memory
  defdelegate put(entry), to: Chassis.Candidate.Registry.Store.Memory
  defdelegate put(store, entry), to: Chassis.Candidate.Registry.Store.Memory
  defdelegate get(store, ref), to: Chassis.Candidate.Registry.Store.Memory
  defdelegate list(store, opts \\ []), to: Chassis.Candidate.Registry.Store.Memory
end

defmodule Chassis.Candidate.Registry do
  @moduledoc "Candidate registry facade."

  alias Chassis.Candidate.Registry.Entry
  alias Chassis.Candidate.Registry.Store.Memory
  alias Chassis.Evolution.Receipts
  alias Chassis.Evolution.Receipts.Store.Memory, as: ReceiptMemory

  @spec register(map(), keyword()) :: {:ok, Entry.t()} | {:error, term()}
  def register(attrs, opts \\ []) when is_map(attrs) do
    with {:ok, entry} <- build_entry(attrs),
         {:ok, stored} <- Memory.put(store(opts), entry),
         :ok <- write_candidate_patch_receipt(stored, attrs, opts) do
      {:ok, stored}
    end
  end

  @spec attach(map(), keyword()) :: {:ok, Entry.t()} | {:error, term()}
  def attach(attrs, opts \\ []), do: register(attrs, opts)

  @spec update_state(String.t(), atom(), keyword()) :: {:ok, Entry.t()} | {:error, term()}
  def update_state(candidate_ref, state, opts \\ []) do
    with :ok <- validate_state(state),
         {:ok, entry} <- get(candidate_ref, opts) do
      update_entry(entry, %{last_state: state}, opts, :state_update)
    end
  end

  @spec attach_digest(String.t(), atom(), String.t(), keyword()) ::
          {:ok, Entry.t()} | {:error, term()}
  def attach_digest(candidate_ref, field, digest, opts \\ [])

  def attach_digest(candidate_ref, field, digest, opts)
      when field in [:candidate_image_digest, :release_digest] and is_binary(digest) do
    with {:ok, entry} <- get(candidate_ref, opts) do
      update_entry(entry, %{field => digest}, opts, :digest_attached)
    end
  end

  def attach_digest(_candidate_ref, field, _digest, _opts),
    do: {:error, {:invalid_digest_field, field}}

  @spec attach_score_matrix(String.t(), String.t(), keyword()) ::
          {:ok, Entry.t()} | {:error, term()}
  def attach_score_matrix(candidate_ref, score_matrix_ref, opts \\ [])
      when is_binary(score_matrix_ref) do
    with {:ok, entry} <- get(candidate_ref, opts) do
      update_entry(entry, %{score_matrix_ref: score_matrix_ref}, opts, :score_matrix_attached)
    end
  end

  @spec attach_authority(String.t(), String.t(), keyword()) :: {:ok, Entry.t()} | {:error, term()}
  def attach_authority(candidate_ref, authority_ref, opts \\ []) when is_binary(authority_ref) do
    with {:ok, entry} <- get(candidate_ref, opts) do
      update_entry(entry, %{authority_ref: authority_ref}, opts, :authority_attached)
    end
  end

  @spec attach_consent(String.t(), String.t(), keyword()) :: {:ok, Entry.t()} | {:error, term()}
  def attach_consent(candidate_ref, operator_consent_ref, opts \\ [])
      when is_binary(operator_consent_ref) do
    with {:ok, entry} <- get(candidate_ref, opts) do
      update_entry(entry, %{operator_consent_ref: operator_consent_ref}, opts, :consent_attached)
    end
  end

  @spec attach_swap(String.t(), String.t(), keyword()) :: {:ok, Entry.t()} | {:error, term()}
  def attach_swap(candidate_ref, promotion_receipt_ref, opts \\ [])
      when is_binary(promotion_receipt_ref) do
    with {:ok, entry} <- get(candidate_ref, opts) do
      update_entry(entry, %{promotion_receipt_ref: promotion_receipt_ref}, opts, :swap_attached)
    end
  end

  @spec attach_rollback(String.t(), String.t(), keyword()) :: {:ok, Entry.t()} | {:error, term()}
  def attach_rollback(candidate_ref, rollback_ref, opts \\ []) when is_binary(rollback_ref) do
    with {:ok, entry} <- get(candidate_ref, opts) do
      update_entry(entry, %{rollback_ref: rollback_ref}, opts, :rollback_attached)
    end
  end

  @spec get(String.t(), keyword()) :: {:ok, Entry.t()} | {:error, :not_found}
  def get(candidate_ref, opts \\ []), do: Memory.get(store(opts), candidate_ref)

  @spec list(keyword()) :: [Entry.t()]
  def list(opts \\ []), do: opts |> store() |> Memory.list(opts)

  @spec ensure_fixture_candidate(keyword()) :: {:ok, Entry.t()}
  def ensure_fixture_candidate(opts \\ []) do
    case get("cand:dev:smoke", opts) do
      {:ok, entry} -> {:ok, entry}
      {:error, :not_found} -> register(fixture(), opts)
    end
  end

  @spec fixture() :: map()
  def fixture do
    %{
      candidate_ref: "cand:dev:smoke",
      tenant_ref: "tenant:dev",
      installation_ref: "installation:dev",
      base_release_ref: "release:base:dev",
      base_image_digest: "sha256:base",
      patch_digest: "sha256:patch",
      failure_batch_ref: "failure_batch:phase24",
      trace_id: "trace:phase24",
      last_state: :patching,
      raw_prompt: "fixture prompt used only before registry redaction"
    }
  end

  @spec jsonable_entry(Entry.t()) :: map()
  def jsonable_entry(%Entry{} = entry) do
    entry
    |> Map.from_struct()
    |> Map.update!(:last_state, &Atom.to_string/1)
    |> encode_datetimes([:created_at, :updated_at])
  end

  defp build_entry(attrs) do
    {:ok, Entry.new!(attrs)}
  rescue
    exception in ArgumentError ->
      {:error, {:invalid_candidate_entry, Exception.message(exception)}}
  end

  defp update_entry(%Entry{} = entry, changes, opts, receipt_kind) do
    updated =
      struct!(
        Entry,
        Map.merge(Map.from_struct(entry), Map.put(changes, :updated_at, DateTime.utc_now()))
      )

    with {:ok, stored} <- Memory.put(store(opts), updated),
         :ok <- write_mutation_receipt(stored, receipt_kind, opts) do
      {:ok, stored}
    end
  end

  defp validate_state(state) do
    if state in Chassis.Evolution.States.all(),
      do: :ok,
      else: {:error, {:invalid_state, state}}
  end

  defp write_candidate_patch_receipt(%Entry{} = entry, attrs, opts) do
    record =
      Receipts.CandidatePatchRecord.new!(%{
        tenant_ref: entry.tenant_ref,
        installation_ref: entry.installation_ref || "installation:unknown",
        trace_id: entry.trace_id,
        candidate_ref: entry.candidate_ref,
        base_release_ref: entry.base_release_ref,
        base_image_digest: entry.base_image_digest,
        patch_digest: entry.patch_digest,
        diff_ref: Map.get(attrs, :diff_ref, "diff:#{entry.candidate_ref}"),
        failure_batch_ref: entry.failure_batch_ref,
        summary: %{bytes: "candidate patch #{entry.candidate_ref}", max_bytes: 256},
        inserted_at: entry.updated_at
      })

    put_receipt(record, opts)
  end

  defp write_mutation_receipt(%Entry{} = entry, receipt_kind, opts) do
    record =
      case receipt_kind do
        :state_update ->
          Receipts.EvolutionStartRecord.new!(%{
            tenant_ref: entry.tenant_ref,
            installation_ref: entry.installation_ref || "installation:unknown",
            trace_id: entry.trace_id,
            evolution_run_ref: "evolution-run:#{entry.candidate_ref}",
            failure_batch_ref: entry.failure_batch_ref,
            started_at: entry.updated_at,
            summary: %{bytes: "candidate state #{entry.last_state}", max_bytes: 256},
            inserted_at: entry.updated_at
          })

        :score_matrix_attached ->
          Receipts.ScoreMatrixRecord.new!(%{
            tenant_ref: entry.tenant_ref,
            installation_ref: entry.installation_ref || "installation:unknown",
            trace_id: entry.trace_id,
            score_matrix_ref: entry.score_matrix_ref,
            candidate_ref: entry.candidate_ref,
            regression_gate: :passed,
            confidence: 1.0,
            summary: %{bytes: "score matrix attached", max_bytes: 256},
            inserted_at: entry.updated_at
          })

        :authority_attached ->
          Receipts.PromotionIntentRecord.new!(%{
            tenant_ref: entry.tenant_ref,
            installation_ref: entry.installation_ref || "installation:unknown",
            trace_id: entry.trace_id,
            promotion_ref: "promotion-intent:#{entry.candidate_ref}",
            candidate_ref: entry.candidate_ref,
            target_installation_ref: entry.installation_ref || "installation:unknown",
            issued_at: entry.updated_at,
            summary: %{bytes: "authority #{entry.authority_ref}", max_bytes: 256},
            inserted_at: entry.updated_at
          })

        :consent_attached ->
          Receipts.OperatorConsentRecord.new!(%{
            tenant_ref: entry.tenant_ref,
            installation_ref: entry.installation_ref || "installation:unknown",
            trace_id: entry.trace_id,
            operator_consent_ref: entry.operator_consent_ref,
            candidate_ref: entry.candidate_ref,
            decision: :approved,
            recorded_at: entry.updated_at,
            actor_ref: "operator:registry",
            summary: %{bytes: "operator consent attached", max_bytes: 256},
            inserted_at: entry.updated_at
          })

        :swap_attached ->
          Receipts.PromotionRecord.new!(%{
            tenant_ref: entry.tenant_ref,
            installation_ref: entry.installation_ref || "installation:unknown",
            trace_id: entry.trace_id,
            promotion_ref: entry.promotion_receipt_ref,
            swap_ref: "swap:#{entry.candidate_ref}",
            outcome: :committed,
            committed_at_or_rolled_back_at: entry.updated_at,
            summary: %{bytes: "promotion receipt attached", max_bytes: 256},
            inserted_at: entry.updated_at
          })

        :rollback_attached ->
          Receipts.EvolutionRollbackRecord.new!(%{
            tenant_ref: entry.tenant_ref,
            installation_ref: entry.installation_ref || "installation:unknown",
            trace_id: entry.trace_id,
            rollback_ref: entry.rollback_ref,
            swap_ref: "swap:#{entry.candidate_ref}",
            restored_artifact_digest: entry.release_digest || entry.patch_digest,
            rolled_back_at: entry.updated_at,
            summary: %{bytes: "rollback attached", max_bytes: 256},
            inserted_at: entry.updated_at
          })

        :digest_attached ->
          nil
      end

    if is_nil(record), do: :ok, else: put_receipt(record, opts)
  end

  defp put_receipt(record, opts) do
    case Keyword.fetch(opts, :receipts_store) do
      {:ok, receipt_store} ->
        case ReceiptMemory.put(receipt_store, record) do
          {:ok, _record} -> :ok
          {:error, reason} -> {:error, {:receipt_write_failed, reason}}
        end

      :error ->
        case ReceiptMemory.put(record) do
          {:ok, _record} -> :ok
          {:error, reason} -> {:error, {:receipt_write_failed, reason}}
        end
    end
  end

  defp store(opts), do: Keyword.get_lazy(opts, :store, &default_store/0)

  defp default_store do
    case Process.whereis(Memory) do
      nil ->
        {:ok, pid} = Memory.start_link()
        pid

      pid ->
        pid
    end
  end

  defp encode_datetimes(map, fields) do
    Enum.reduce(fields, map, fn field, acc ->
      Map.update(acc, field, nil, fn
        %DateTime{} = datetime -> DateTime.to_iso8601(datetime)
        other -> other
      end)
    end)
  end
end
