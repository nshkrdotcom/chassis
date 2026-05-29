defmodule Chassis.Core do
  @moduledoc "Core orchestration facade."
end

defmodule Chassis.Core.Engine do
  @moduledoc "Deployment state machine with fail-closed recovery."
  use GenServer
  @states [:offline, :provisioning, :booting, :healthy, :degraded, :failed, :recovering]

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []),
    do: GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))

  @impl true
  def init(_opts), do: {:ok, %{state: :offline, events: []}}

  @spec state(GenServer.server()) :: atom()
  def state(server \\ __MODULE__), do: GenServer.call(server, :state)

  @spec transition(GenServer.server(), atom()) :: {:ok, atom()} | {:error, term()}
  def transition(server \\ __MODULE__, next), do: GenServer.call(server, {:transition, next})

  @spec recover(GenServer.server()) :: {:ok, atom()}
  def recover(server \\ __MODULE__), do: GenServer.call(server, :recover)

  @impl true
  def handle_call(:state, _from, state), do: {:reply, state.state, state}

  def handle_call(:recover, _from, state),
    do: {:reply, {:ok, :recovering}, %{state | state: :recovering}}

  def handle_call({:transition, next}, _from, %{state: :failed} = state)
      when next != :recovering do
    {:reply, {:error, :recover_required}, state}
  end

  def handle_call({:transition, next}, _from, state) when next in @states do
    if legal?(state.state, next) do
      {:reply, {:ok, next},
       %{state | state: next, events: [{next, DateTime.utc_now()} | state.events]}}
    else
      {:reply, {:error, {:illegal_transition, state.state, next}}, state}
    end
  end

  defp legal?(:offline, next), do: next in [:provisioning, :failed]
  defp legal?(:provisioning, next), do: next in [:booting, :failed]
  defp legal?(:booting, next), do: next in [:healthy, :failed]
  defp legal?(:healthy, next), do: next in [:degraded, :failed]
  defp legal?(:degraded, next), do: next in [:recovering, :failed]
  defp legal?(:recovering, next), do: next in [:healthy, :failed]
  defp legal?(_current, _next), do: false
end

defmodule Chassis.Core.Dispatcher do
  @moduledoc "Routes requests through adapter callbacks."
  @spec dispatch(module(), {atom(), map(), keyword()}) :: {:ok, map()} | {:error, term()}
  def dispatch(adapter, {function, payload, opts})
      when function in [:prepare, :start, :stop, :health] do
    if function_exported?(adapter, function, 2),
      do: apply(adapter, function, [payload, opts]),
      else: {:error, :adapter_callback_missing}
  end
end

defmodule Chassis.Core.NodeRegistry do
  @moduledoc "ETS-backed node lifecycle registry."
  @table :chassis_node_registry

  @spec put(String.t(), atom()) :: :ok
  def put(node_ref, status) do
    ensure_table()
    :ets.insert(@table, {node_ref, %{node_ref: node_ref, status: status, at: DateTime.utc_now()}})
    :ok
  end

  @spec get(String.t()) :: {:ok, map()} | {:error, :not_found}
  def get(node_ref) do
    ensure_table()

    case :ets.lookup(@table, node_ref) do
      [{^node_ref, value}] -> {:ok, value}
      [] -> {:error, :not_found}
    end
  end

  defp ensure_table do
    case :ets.info(@table) do
      :undefined -> :ets.new(@table, [:named_table, :public])
      _info -> @table
    end
  end
end
