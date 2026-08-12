defmodule Chassis.Receipts do
  @moduledoc """
  Receipts package. Provides:

  * `redact/1` — generic recursive redactor for any map/list containing
    sensitive key fragments (`secret`, `password`, `material`, `token`, etc).
  * `new_ref/1` — generates a stable opaque `<prefix>:<random>` reference.

  Per-record types live under `Chassis.Receipts.*Record` and are typed
  Elixir structs (not Ash resources yet — the AshPostgres backend is
  DEFERRED until Phases 11/18 wire a real database; see
  `docs/implementation_notes/phase_02_report.md`). Today, the
  `Chassis.Receipts.Store.Memory` GenServer is the canonical reference
  implementation of the `Chassis.Receipts.Store` behaviour and exercises
  the same `put → after_action → projection` flow that the future Ash
  resource will use.
  """

  @sensitive_fragments ~w(secret password private_key material token credential authorization
                          cookie bearer api_key access_token refresh_token webhook
                          oauth client_secret session_id raw_credential)

  @doc """
  Redact any map/list recursively: any key whose downcased string form
  contains a fragment from the sensitive list is replaced with
  `"[REDACTED]"`. Non-sensitive values are recursed into.
  """
  @spec redact(term()) :: term()
  def redact(map) when is_map(map) and not is_struct(map) do
    Map.new(map, fn {key, value} ->
      if sensitive_key?(key), do: {key, "[REDACTED]"}, else: {key, redact(value)}
    end)
  end

  def redact(list) when is_list(list), do: Enum.map(list, &redact/1)
  def redact(value), do: value

  @doc "Generate a new `<prefix>:<random8>` receipt reference."
  @spec new_ref(String.t()) :: String.t()
  def new_ref(prefix),
    do: prefix <> ":" <> Base.encode16(:crypto.strong_rand_bytes(4), case: :lower)

  @doc false
  @spec sensitive_key?(term()) :: boolean()
  def sensitive_key?(key) do
    downcased = key |> to_string() |> String.downcase()
    Enum.any?(@sensitive_fragments, &String.contains?(downcased, &1))
  end
end

defmodule Chassis.Receipts.Store do
  @moduledoc """
  Receipt store behaviour. Concrete backends:

  * `Chassis.Receipts.Store.Memory` — GenServer-backed ETS store with a
    JSONL appender (this phase).
  * `Chassis.Receipts.Store.AshPostgres` — DEFERRED until the workspace
    has a real Postgres + Ash setup (Phase 11+).

  Every `put/2` call routes the record through `after_action/1` callbacks
  for AITrace, Metrics, and Mezzanine projection publishing. In Phase 2
  those callbacks are no-ops returning `:ok`; later phases inject real
  publishers when the relevant packages activate (per the
  `0517_mezzanine_deployment_workflow_spec.md` §5 pattern).
  """

  @typedoc "Receipt record — any of the typed structs in Chassis.Receipts.*"
  @type receipt_record :: struct()

  @callback put(GenServer.server(), receipt_record()) ::
              {:ok, receipt_record()} | {:error, term()}

  @callback get(GenServer.server(), String.t()) ::
              {:ok, receipt_record()} | {:error, :not_found}

  @callback list(GenServer.server(), keyword()) :: [receipt_record()]
  @callback delete(GenServer.server(), String.t()) :: :ok
end

defmodule Chassis.Receipts.DeploymentRecord do
  @moduledoc "Successful or failed deployment receipt."
  @enforce_keys [:receipt_ref, :app_ref, :profile_ref, :env, :status]
  defstruct [
    :receipt_ref,
    :app_ref,
    :profile_ref,
    :env,
    :status,
    :authority_ref,
    :tenant_ref,
    :written_at,
    secret_refs: [],
    labels: %{},
    material: nil,
    password: nil
  ]

  @type t :: %__MODULE__{
          receipt_ref: String.t(),
          app_ref: String.t(),
          profile_ref: String.t(),
          env: atom(),
          status: :active | :failed | :rolled_back | :pending,
          authority_ref: String.t() | nil,
          tenant_ref: String.t() | nil,
          secret_refs: [String.t()],
          labels: map(),
          material: String.t() | nil,
          password: String.t() | nil,
          written_at: DateTime.t() | nil
        }

  defimpl Inspect do
    def inspect(rec, _opts) do
      masked = %{
        rec
        | material: redact_or_nil(rec.material),
          password: redact_or_nil(rec.password),
          labels: Chassis.Receipts.redact(rec.labels)
      }

      "%Chassis.Receipts.DeploymentRecord{" <> body(masked) <> "}"
    end

    defp redact_or_nil(nil), do: nil
    defp redact_or_nil(_), do: "[REDACTED]"

    defp body(rec),
      do:
        rec
        |> Map.from_struct()
        |> Enum.sort()
        |> Enum.map_join(", ", fn {k, v} -> "#{k}: #{Kernel.inspect(v)}" end)
  end
end

defmodule Chassis.Receipts.ProvisioningRecord do
  @moduledoc "Provisioning attempt receipt."
  @enforce_keys [:receipt_ref, :host_ref, :attempt, :steps, :status]
  defstruct [
    :receipt_ref,
    :host_ref,
    :attempt,
    :steps,
    :status,
    :written_at,
    error: nil,
    duration_ms: 0
  ]

  @type t :: %__MODULE__{
          receipt_ref: String.t(),
          host_ref: String.t(),
          attempt: pos_integer(),
          steps: [atom()],
          status: :ok | :failed | :timed_out,
          error: term() | nil,
          duration_ms: non_neg_integer(),
          written_at: DateTime.t() | nil
        }
end

defmodule Chassis.Receipts.RollbackRecord do
  @moduledoc """
  Rollback receipt. `trigger` must be one of the documented values:
  `:operator`, `:metabolic_self_healing`, `:workflow_failure`.
  """
  @enforce_keys [:receipt_ref, :deployment_receipt_ref, :trigger, :status]
  defstruct [
    :receipt_ref,
    :deployment_receipt_ref,
    :trigger,
    :status,
    :authority_ref,
    :written_at,
    rationale: nil
  ]

  @type trigger :: :operator | :metabolic_self_healing | :workflow_failure

  @type t :: %__MODULE__{
          receipt_ref: String.t(),
          deployment_receipt_ref: String.t(),
          trigger: trigger(),
          status: :rolled_back | :failed,
          authority_ref: String.t() | nil,
          rationale: String.t() | nil,
          written_at: DateTime.t() | nil
        }

  @doc false
  @spec valid_trigger?(atom()) :: boolean()
  def valid_trigger?(t), do: t in [:operator, :metabolic_self_healing, :workflow_failure]
end

defmodule Chassis.Receipts.KeyRotationRecord do
  @moduledoc "SSH/SOPS key rotation receipt."
  @enforce_keys [:receipt_ref, :key_ref, :rotated_at, :fingerprint]
  defstruct [:receipt_ref, :key_ref, :rotated_at, :fingerprint, :written_at, actor_ref: nil]
end

defmodule Chassis.Receipts.MaterializationRecord do
  @moduledoc "Secret lease materialization receipt."
  @enforce_keys [:receipt_ref, :secret_ref, :lease_ref, :materialized_at]
  defstruct [:receipt_ref, :secret_ref, :lease_ref, :materialized_at, :written_at, expires_at: nil]
end

defmodule Chassis.Receipts.BoundaryRecord do
  @moduledoc "Ring 0 boundary decision audit."
  @enforce_keys [:receipt_ref, :protocol, :decision]
  defstruct [
    :receipt_ref,
    :protocol,
    :decision,
    :rationale,
    :authority_ref,
    :tenant_ref,
    :written_at
  ]
end

defmodule Chassis.Receipts.TenantAwareDeploymentReceipt do
  @moduledoc "View combining DeploymentRecord with tenant guard outcomes."
  @enforce_keys [:receipt_ref, :deployment_receipt_ref, :tenant_ref]
  defstruct [
    :receipt_ref,
    :deployment_receipt_ref,
    :tenant_ref,
    :written_at,
    residency_passed?: false,
    isolation_passed?: false
  ]
end

defmodule Chassis.Receipts.AITraceReceipt do
  @moduledoc "Links a Chassis receipt to an AITrace export ref."
  @enforce_keys [:receipt_ref, :chassis_receipt_ref, :aitrace_export_ref, :exported_at]
  defstruct [
    :receipt_ref,
    :chassis_receipt_ref,
    :aitrace_export_ref,
    :exported_at,
    :written_at
  ]
end

defmodule Chassis.Receipts.Store.Memory do
  @moduledoc """
  GenServer-backed in-memory receipt store with optional JSONL appender.

  Implements `Chassis.Receipts.Store`. Each `put/2`:

  1. Validates the record is one of the documented `Chassis.Receipts.*Record` types.
  2. Stamps `written_at` to `DateTime.utc_now/0`.
  3. Inserts into a private ETS table keyed by `receipt_ref`.
  4. If `jsonl_path:` was provided at start, appends a redacted JSON line.
  5. Invokes the registered `after_action` callbacks (AITrace, Metrics,
     Mezzanine projection). Today those are stub callbacks returning `:ok`;
     they are replaced with real publishers in Phases 14, 15, and 16
     respectively.

  Returns `{:error, {:invalid_record, reason}}` for malformed input. Never
  fabricates a success path for unsupported callbacks.
  """
  use GenServer
  @behaviour Chassis.Receipts.Store

  alias Chassis.Receipts.{
    AITraceReceipt,
    BoundaryRecord,
    DeploymentRecord,
    KeyRotationRecord,
    MaterializationRecord,
    ProvisioningRecord,
    RollbackRecord,
    TenantAwareDeploymentReceipt
  }

  @known_records [
    DeploymentRecord,
    ProvisioningRecord,
    RollbackRecord,
    KeyRotationRecord,
    MaterializationRecord,
    BoundaryRecord,
    TenantAwareDeploymentReceipt,
    AITraceReceipt
  ]

  @doc false
  def known_records, do: @known_records

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    case name do
      nil -> GenServer.start_link(__MODULE__, opts, [])
      _ -> GenServer.start_link(__MODULE__, opts, name: name)
    end
  end

  @impl Chassis.Receipts.Store
  def put(server, record), do: GenServer.call(server, {:put, record})

  @impl Chassis.Receipts.Store
  def get(server, ref), do: GenServer.call(server, {:get, ref})

  @impl Chassis.Receipts.Store
  def list(server, opts), do: GenServer.call(server, {:list, opts})

  @impl Chassis.Receipts.Store
  def delete(server, ref), do: GenServer.call(server, {:delete, ref})

  # GenServer callbacks

  @impl GenServer
  def init(opts) do
    table = :ets.new(:chassis_receipts_memory, [:set, :protected, read_concurrency: true])

    state = %{
      table: table,
      jsonl_path: Keyword.get(opts, :jsonl_path),
      after_actions: Keyword.get(opts, :after_actions, [])
    }

    if state.jsonl_path, do: File.mkdir_p!(Path.dirname(state.jsonl_path))
    {:ok, state}
  end

  @impl GenServer
  def handle_call({:put, record}, _from, state) do
    case validate(record) do
      {:ok, stamped} ->
        :ets.insert(state.table, {stamped.receipt_ref, stamped})
        maybe_append_jsonl(state, stamped)
        run_after_actions(state, stamped)
        {:reply, {:ok, stamped}, state}

      {:error, reason} ->
        {:reply, {:error, {:invalid_record, reason}}, state}
    end
  end

  def handle_call({:get, ref}, _from, state) do
    case :ets.lookup(state.table, ref) do
      [{^ref, record}] -> {:reply, {:ok, record}, state}
      [] -> {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:list, opts}, _from, state) do
    kind = Keyword.get(opts, :kind)

    records =
      state.table
      |> :ets.tab2list()
      |> Enum.map(fn {_ref, rec} -> rec end)
      |> Enum.filter(fn rec ->
        is_nil(kind) or rec.__struct__ == kind
      end)

    {:reply, records, state}
  end

  def handle_call({:delete, ref}, _from, state) do
    :ets.delete(state.table, ref)
    {:reply, :ok, state}
  end

  defp validate(%mod{} = record) when mod in @known_records do
    cond do
      not is_binary(record.receipt_ref) ->
        {:error, :missing_receipt_ref}

      mod == RollbackRecord and not RollbackRecord.valid_trigger?(record.trigger) ->
        {:error, {:invalid_trigger, record.trigger}}

      true ->
        {:ok, %{record | written_at: DateTime.utc_now()}}
    end
  end

  defp validate(other), do: {:error, {:unknown_record_shape, inspect(other)}}

  defp maybe_append_jsonl(%{jsonl_path: nil}, _record), do: :ok

  defp maybe_append_jsonl(%{jsonl_path: path}, record) do
    redacted =
      record
      |> Map.from_struct()
      |> Chassis.Receipts.redact()
      |> Map.put(:__record__, inspect(record.__struct__))

    json = Jason.encode!(redacted)
    File.write!(path, json <> "\n", [:append])
  end

  defp run_after_actions(%{after_actions: []}, _record), do: :ok

  defp run_after_actions(%{after_actions: callbacks}, record) do
    Enum.each(callbacks, fn cb ->
      try do
        cb.(record)
      rescue
        e -> require Logger; Logger.warning("after_action raised: #{Exception.message(e)}")
      end
    end)
  end
end

defmodule Chassis.Receipts.Store.AshPostgres do
  @moduledoc """
  AshPostgres backend placeholder. The real Ash resource + Postgres
  migrations are DEFERRED until the workspace has a Postgres dev DB
  (Phase 11 / Phase 18). Every callback returns
  `{:error, {:not_implemented, __MODULE__}}` per
  `0541_implementation_readiness_corrections.md` §1 row 4. This prevents
  a CLI or upstream caller from accidentally counting an AshPostgres
  receipt write as a success when no DB is configured.
  """
  @behaviour Chassis.Receipts.Store

  @impl true
  def put(_server, _record), do: {:error, {:not_implemented, __MODULE__}}
  @impl true
  def get(_server, _ref), do: {:error, {:not_implemented, __MODULE__}}
  @impl true
  def list(_server, _opts), do: {:error, {:not_implemented, __MODULE__}}
  @impl true
  def delete(_server, _ref), do: {:error, {:not_implemented, __MODULE__}}
end
