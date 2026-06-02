defmodule Chassis.Core do
  @moduledoc """
  Core orchestration facade. Exposes the documented surface:

  * `Chassis.Core.Engine` — deployment state machine GenServer.
  * `Chassis.Core.Dispatcher` — routes adapter calls through the
    `Chassis.Contracts.Adapter` behaviour.
  * `Chassis.Core.NodeRegistry` — per-process, ETS-backed lifecycle tracker.

  The Engine NEVER references concrete adapter modules. It uses
  `Chassis.Contracts.Adapter` plus `Chassis.Core.Dispatcher` to talk to the
  outside world. Crash recovery rehydrates state from the configured
  `Chassis.Receipts.Store` (today: `Chassis.Receipts.Store.Memory`).
  """
end

defmodule Chassis.Core.Engine do
  @moduledoc """
  Deployment state machine. States and legal transitions:

      :offline      -> :provisioning, :failed
      :provisioning -> :booting, :failed
      :booting      -> :healthy, :failed
      :healthy      -> :degraded, :failed
      :degraded     -> :recovering, :failed
      :recovering   -> :healthy, :failed
      :failed       -> {:error, :recover_required}  (use `recover/1`)

  Every transition optionally writes a `Chassis.Receipts.DeploymentRecord`
  to the configured `receipts_store:` GenServer. On startup, if a store is
  given, the engine rehydrates `state` from the most recent record.

  Fail-closed: from `:failed`, the only path forward is `recover/1`, which
  moves to `:recovering`. Any other `transition/2` from `:failed` returns
  `{:error, :recover_required}`.
  """
  use GenServer

  alias Chassis.Receipts.{DeploymentRecord, Store}

  @type state ::
          :offline | :provisioning | :booting | :healthy | :degraded | :failed | :recovering

  @states [:offline, :provisioning, :booting, :healthy, :degraded, :failed, :recovering]

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)

    case name do
      nil -> GenServer.start_link(__MODULE__, opts, [])
      _ -> GenServer.start_link(__MODULE__, opts, name: name)
    end
  end

  @spec state(GenServer.server()) :: state()
  def state(server \\ __MODULE__), do: GenServer.call(server, :state)

  @spec events(GenServer.server()) :: [%{to: state(), at: DateTime.t()}]
  def events(server \\ __MODULE__), do: GenServer.call(server, :events)

  @spec transition(GenServer.server(), state(), keyword()) ::
          {:ok, state()} | {:error, term()}
  def transition(server \\ __MODULE__, next, opts \\ []) do
    GenServer.call(server, {:transition, next, opts})
  end

  @spec recover(GenServer.server()) :: {:ok, :recovering}
  def recover(server \\ __MODULE__), do: GenServer.call(server, :recover)

  # GenServer

  @impl true
  def init(opts) do
    store = Keyword.get(opts, :receipts_store)
    {hydrated_state, events} = rehydrate(store)

    {:ok,
     %{
       state: hydrated_state,
       events: events,
       receipts_store: store,
       app_ref: Keyword.get(opts, :app_ref),
       profile_ref: Keyword.get(opts, :profile_ref),
       env: Keyword.get(opts, :env)
     }}
  end

  @impl true
  def handle_call(:state, _from, st), do: {:reply, st.state, st}
  def handle_call(:events, _from, st), do: {:reply, st.events, st}

  def handle_call(:recover, _from, %{state: :failed} = st) do
    next_st = %{st | state: :recovering, events: push_event(:recovering, st.events)}
    maybe_emit_receipt(next_st, :recovering, [])
    {:reply, {:ok, :recovering}, next_st}
  end

  def handle_call(:recover, _from, st) do
    next_st = %{st | state: :recovering, events: push_event(:recovering, st.events)}
    maybe_emit_receipt(next_st, :recovering, [])
    {:reply, {:ok, :recovering}, next_st}
  end

  def handle_call({:transition, next, _opts}, _from, st) when next not in @states do
    {:reply, {:error, {:unknown_state, next}}, st}
  end

  def handle_call({:transition, next, _opts}, _from, %{state: :failed} = st)
      when next != :recovering do
    {:reply, {:error, :recover_required}, st}
  end

  def handle_call({:transition, next, opts}, _from, st) do
    if legal?(st.state, next) do
      next_st = %{st | state: next, events: push_event(next, st.events)}
      maybe_emit_receipt(next_st, next, opts)
      {:reply, {:ok, next}, next_st}
    else
      {:reply, {:error, {:illegal_transition, st.state, next}}, st}
    end
  end

  # state-machine table

  defp legal?(:offline, :provisioning), do: true
  defp legal?(:offline, :failed), do: true
  defp legal?(:provisioning, :booting), do: true
  defp legal?(:provisioning, :failed), do: true
  defp legal?(:booting, :healthy), do: true
  defp legal?(:booting, :failed), do: true
  defp legal?(:healthy, :degraded), do: true
  defp legal?(:healthy, :failed), do: true
  defp legal?(:degraded, :recovering), do: true
  defp legal?(:degraded, :failed), do: true
  defp legal?(:recovering, :healthy), do: true
  defp legal?(:recovering, :failed), do: true
  defp legal?(_from, _to), do: false

  defp push_event(to, events), do: [%{to: to, at: DateTime.utc_now()} | events]

  defp maybe_emit_receipt(%{receipts_store: nil}, _state, _opts), do: :ok

  defp maybe_emit_receipt(%{receipts_store: store} = st, state, opts) do
    record = %DeploymentRecord{
      receipt_ref: Chassis.Receipts.new_ref("receipt:deployment"),
      app_ref: Keyword.get(opts, :app_ref) || st.app_ref || "unknown",
      profile_ref: Keyword.get(opts, :profile_ref) || st.profile_ref || "unknown",
      env: Keyword.get(opts, :env) || st.env || :dev,
      status: state,
      authority_ref: Keyword.get(opts, :authority_ref),
      tenant_ref: Keyword.get(opts, :tenant_ref)
    }

    case Store.Memory.put(store, record) do
      {:ok, _} -> :ok
      _ -> :ok
    end
  end

  defp rehydrate(nil), do: {:offline, []}

  defp rehydrate(store) do
    case Store.Memory.list(store, kind: DeploymentRecord) do
      [] ->
        {:offline, []}

      records ->
        sorted =
          records
          |> Enum.filter(& &1.written_at)
          |> Enum.sort_by(& &1.written_at, {:desc, DateTime})

        latest = List.first(sorted)
        events = Enum.map(sorted, fn r -> %{to: r.status, at: r.written_at} end)

        if latest && latest.status in @states do
          {latest.status, events}
        else
          {:offline, events}
        end
    end
  end
end

defmodule Chassis.Core.Dispatcher do
  @moduledoc """
  Routes a `{callback, payload, opts}` triple to a `Chassis.Contracts.Adapter`
  implementation. Refuses callbacks not in the documented behaviour and
  refuses modules that do not declare the behaviour. Rescues adapter raises
  into `{:error, {:adapter_raised, message}}` so a misbehaving adapter
  cannot crash the engine.
  """

  @supported [:prepare, :start, :stop, :health]

  @spec dispatch(module(), {atom(), map(), keyword()}) :: {:ok, map()} | {:error, term()}
  def dispatch(_adapter, {callback, _payload, _opts}) when callback not in @supported do
    {:error, {:unsupported_callback, callback}}
  end

  def dispatch(adapter, {callback, payload, opts}) do
    if implements_adapter?(adapter) do
      try do
        apply(adapter, callback, [payload, opts])
      rescue
        e -> {:error, {:adapter_raised, Exception.message(e)}}
      end
    else
      {:error, {:not_an_adapter, adapter}}
    end
  end

  defp implements_adapter?(module) do
    Code.ensure_loaded?(module) and
      function_exported?(module, :module_info, 1) and
      Chassis.Contracts.Adapter in (module.module_info(:attributes)[:behaviour] || [])
  end
end

defmodule Chassis.Core.NodeRegistry do
  @moduledoc """
  Per-process ETS-backed node lifecycle tracker. Each `start_link/1` allocates
  a fresh table, so concurrent tests and concurrent engines do not collide.

  * `put/3` — record a new status for a node_ref (append; preserves history).
  * `get/2` — fetch the **most recent** status row for a node_ref.
  * `events/2` — full ordered history for a node_ref.
  * `list/1` — most-recent row for every tracked node_ref.
  """
  use GenServer

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)

    case name do
      nil -> GenServer.start_link(__MODULE__, opts, [])
      _ -> GenServer.start_link(__MODULE__, opts, name: name)
    end
  end

  @spec put(GenServer.server(), String.t(), atom()) :: :ok
  def put(server, node_ref, status), do: GenServer.call(server, {:put, node_ref, status})

  @spec get(GenServer.server(), String.t()) :: {:ok, map()} | {:error, :not_found}
  def get(server, node_ref), do: GenServer.call(server, {:get, node_ref})

  @spec events(GenServer.server(), String.t()) :: [map()]
  def events(server, node_ref), do: GenServer.call(server, {:events, node_ref})

  @spec list(GenServer.server()) :: [map()]
  def list(server), do: GenServer.call(server, :list)

  @impl true
  def init(_opts) do
    table = :ets.new(:chassis_node_registry, [:bag, :protected])
    {:ok, %{table: table}}
  end

  @impl true
  def handle_call({:put, node_ref, status}, _from, %{table: t} = st) do
    entry = %{node_ref: node_ref, status: status, at: DateTime.utc_now()}
    :ets.insert(t, {node_ref, entry})
    {:reply, :ok, st}
  end

  def handle_call({:get, node_ref}, _from, %{table: t} = st) do
    case :ets.lookup(t, node_ref) do
      [] -> {:reply, {:error, :not_found}, st}
      rows -> {:reply, {:ok, latest(rows)}, st}
    end
  end

  def handle_call({:events, node_ref}, _from, %{table: t} = st) do
    events =
      t
      |> :ets.lookup(node_ref)
      |> Enum.map(fn {_, entry} -> entry end)
      |> Enum.sort_by(& &1.at, DateTime)

    {:reply, events, st}
  end

  def handle_call(:list, _from, %{table: t} = st) do
    grouped =
      t
      |> :ets.tab2list()
      |> Enum.group_by(fn {ref, _entry} -> ref end, fn {_ref, entry} -> entry end)

    latest_per_node =
      Enum.map(grouped, fn {_ref, rows} -> Enum.max_by(rows, & &1.at, DateTime) end)

    {:reply, latest_per_node, st}
  end

  defp latest(rows) do
    rows
    |> Enum.map(fn {_, entry} -> entry end)
    |> Enum.max_by(& &1.at, DateTime)
  end
end
