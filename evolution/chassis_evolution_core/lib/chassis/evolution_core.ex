defmodule Chassis.Evolution.Core.Transitions do
  @moduledoc "Declarative evolution transition table."

  @transitions %{
    queued: [:evidence_curated, :failed, :stopped],
    evidence_curated: [:planning, :failed, :stopped],
    planning: [:patching, :blocked, :failed, :stopped],
    patching: [:building, :failed, :stopped],
    building: [:trial_provisioning, :failed, :stopped],
    trial_provisioning: [:trial_running, :failed, :stopped],
    trial_running: [:scoring, :failed, :stopped],
    scoring: [:blocked, :converged, :failed, :stopped],
    blocked: [:planning, :stopped, :failed],
    converged: [:awaiting_authority, :stopped],
    awaiting_authority: [:awaiting_operator_consent, :failed, :stopped],
    awaiting_operator_consent: [:promotion_requested, :stopped],
    promotion_requested: [:promoting, :stopped, :failed],
    promoting: [:committed, :rolled_back, :failed]
  }

  @spec allowed?(atom(), atom()) :: boolean()
  def allowed?(from, to), do: to in Map.get(@transitions, from, [])

  @spec table() :: map()
  def table, do: @transitions
end

defmodule Chassis.Evolution.Core.TransitionReceipt do
  @moduledoc "Receipt emitted for an evolution state transition."

  @enforce_keys [
    :receipt_ref,
    :evolution_run_ref,
    :from_state,
    :to_state,
    :event,
    :inserted_at
  ]
  defstruct [
    :receipt_ref,
    :evolution_run_ref,
    :failure_batch_ref,
    :from_state,
    :to_state,
    :event,
    :metadata,
    :inserted_at
  ]

  @type t :: %__MODULE__{}

  @spec new!(map()) :: t()
  def new!(attrs) when is_map(attrs) do
    struct!(__MODULE__, attrs)
  end
end

defmodule Chassis.Evolution.Core.ReceiptLog do
  @moduledoc "Agent-backed transition receipt log for evolution-core recovery."

  alias Chassis.Evolution.Core.TransitionReceipt

  @type log :: pid() | atom()

  @spec start_link(keyword()) :: Agent.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)

    case name do
      nil -> Agent.start_link(fn -> [] end, opts)
      name -> start_named(name, opts)
    end
  end

  @spec append(log(), TransitionReceipt.t()) :: {:ok, TransitionReceipt.t()}
  def append(log, %TransitionReceipt{} = receipt) do
    log = ensure_log(log)
    Agent.update(log, &[receipt | &1])
    {:ok, receipt}
  end

  @spec list(log()) :: [TransitionReceipt.t()]
  def list(log \\ __MODULE__) do
    log
    |> ensure_log()
    |> Agent.get(&Enum.reverse/1)
  end

  @spec latest_state(log(), String.t()) :: atom() | nil
  def latest_state(log, evolution_run_ref) do
    log
    |> list()
    |> Enum.filter(&(&1.evolution_run_ref == evolution_run_ref))
    |> List.last()
    |> case do
      nil -> nil
      receipt -> receipt.to_state
    end
  end

  defp start_named(name, opts) do
    case Agent.start_link(fn -> [] end, Keyword.put(opts, :name, name)) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      other -> other
    end
  end

  defp ensure_log(log) when is_pid(log), do: log

  defp ensure_log(log) when is_atom(log) do
    case Process.whereis(log) do
      nil ->
        {:ok, pid} = start_link(name: log)
        pid

      pid ->
        pid
    end
  end
end

defmodule Chassis.Evolution.Core do
  @moduledoc "Evolution lifecycle state machine."

  use GenServer

  alias Chassis.Evolution.Core.{ReceiptLog, TransitionReceipt, Transitions}
  alias Chassis.Evolution.PromotionPreconditions

  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)

    case name do
      nil -> GenServer.start_link(__MODULE__, opts, [])
      name -> GenServer.start_link(__MODULE__, opts, name: name)
    end
  end

  @impl true
  def init(opts) do
    receipt_log = Keyword.get(opts, :receipt_log, ReceiptLog)
    evolution_run_ref = Keyword.get(opts, :evolution_run_ref) || evolution_run_ref(opts)

    state =
      Keyword.get(opts, :state) ||
        ReceiptLog.latest_state(receipt_log, evolution_run_ref) ||
        :queued

    state = %{
      state: state,
      evolution_run_ref: evolution_run_ref,
      failure_batch_ref: Keyword.get(opts, :failure_batch_ref, "fb:dev:smoke"),
      receipt_log: receipt_log,
      registry: Keyword.get(opts, :registry),
      metadata: %{}
    }

    maybe_register(state)
    {:ok, state}
  end

  def state(server \\ __MODULE__), do: GenServer.call(server, :state)

  def status(server \\ __MODULE__) do
    GenServer.call(server, :status)
  end

  def transition(server \\ __MODULE__, next, metadata \\ %{}) do
    GenServer.call(server, {:transition, next, metadata})
  end

  def stop(server \\ __MODULE__, reason_code \\ :operator_requested) do
    transition(server, :stopped, %{reason_code: reason_code})
  end

  def precondition_check(map) when is_map(map) do
    missing? =
      Enum.any?(PromotionPreconditions.required_fields(), fn field ->
        not Map.has_key?(map, field) or is_nil(Map.get(map, field))
      end)

    cond do
      missing? -> {:error, :missing_field}
      Map.get(map, :regression_gate) != :passed -> {:error, :regression_gate_blocked}
      true -> :ok
    end
  end

  def jsonable(status) when is_map(status) do
    Map.new(status, fn
      {key, value} when is_atom(value) -> {key, Atom.to_string(value)}
      {key, value} -> {key, value}
    end)
  end

  @impl true
  def handle_call(:state, _from, state), do: {:reply, state.state, state}

  def handle_call(:status, _from, state), do: {:reply, public_status(state), state}

  def handle_call({:transition, next, metadata}, _from, state) do
    if Transitions.allowed?(state.state, next) do
      case maybe_check_preconditions(next, metadata) do
        :ok ->
          next_state = record_transition(state, next, metadata)
          {:reply, {:ok, next}, next_state}

        {:error, reason} ->
          {:reply, {:error, reason}, state}
      end
    else
      {:reply, {:error, {:illegal_transition, state.state, next}}, state}
    end
  end

  defp maybe_check_preconditions(:promotion_requested, metadata), do: precondition_check(metadata)
  defp maybe_check_preconditions(_next, _metadata), do: :ok

  defp record_transition(state, next, metadata) do
    receipt =
      TransitionReceipt.new!(%{
        receipt_ref:
          "receipt:evolution_transition:#{state.evolution_run_ref}:#{System.unique_integer([:positive, :monotonic])}",
        evolution_run_ref: state.evolution_run_ref,
        failure_batch_ref: state.failure_batch_ref,
        from_state: state.state,
        to_state: next,
        event: :transition,
        metadata: metadata,
        inserted_at: DateTime.utc_now()
      })

    {:ok, _receipt} = ReceiptLog.append(state.receipt_log, receipt)
    next_state = %{state | state: next, metadata: metadata}
    maybe_register(next_state)
    next_state
  end

  defp maybe_register(%{registry: nil}), do: :ok

  defp maybe_register(state) do
    Chassis.Evolution.Registry.register(state.registry, public_status(state))
  end

  defp public_status(state) do
    %{
      evolution_run_ref: state.evolution_run_ref,
      failure_batch_ref: state.failure_batch_ref,
      state: state.state
    }
  end

  defp evolution_run_ref(opts) do
    batch_ref = Keyword.get(opts, :failure_batch_ref, "fb:dev:smoke")
    "evo:#{batch_ref}"
  end
end

defmodule Chassis.Evolution.Supervisor do
  @moduledoc "Evolution supervisor."
  use Supervisor

  def start_link(opts \\ []), do: Supervisor.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts), do: Supervisor.init([{Chassis.Evolution.Core, []}], strategy: :one_for_one)
end

defmodule Chassis.Evolution.Registry do
  @moduledoc "Evolution run registry."

  @type registry :: pid() | atom()

  @spec start_link(keyword()) :: Agent.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)

    case name do
      nil -> Agent.start_link(fn -> %{} end, opts)
      name -> start_named(name, opts)
    end
  end

  @spec register(registry(), map()) :: :ok
  def register(registry \\ __MODULE__, status) when is_map(status) do
    registry = ensure_registry(registry)
    Agent.update(registry, &Map.put(&1, status.evolution_run_ref, status))
  end

  @spec list(registry()) :: [map()]
  def list(registry \\ __MODULE__) do
    registry
    |> ensure_registry()
    |> Agent.get(&Map.values/1)
    |> Enum.sort_by(& &1.evolution_run_ref)
  end

  defp start_named(name, opts) do
    case Agent.start_link(fn -> %{} end, Keyword.put(opts, :name, name)) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      other -> other
    end
  end

  defp ensure_registry(registry) when is_pid(registry), do: registry

  defp ensure_registry(registry) when is_atom(registry) do
    case Process.whereis(registry) do
      nil ->
        {:ok, pid} = start_link(name: registry)
        pid

      pid ->
        pid
    end
  end
end
