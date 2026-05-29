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

defmodule Chassis.Evolution.Core do
  @moduledoc "Evolution lifecycle state machine."
  use GenServer

  def start_link(opts \\ []),
    do: GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))

  @impl true
  def init(opts), do: {:ok, %{state: Keyword.get(opts, :state, :queued), receipts: []}}
  def state(server \\ __MODULE__), do: GenServer.call(server, :state)
  def transition(server \\ __MODULE__, next), do: GenServer.call(server, {:transition, next})

  def precondition_check(map),
    do:
      if(
        Enum.all?(
          [
            :candidate_ref,
            :score_matrix_ref,
            :authority_ref,
            :operator_consent_ref,
            :rollback_manifest_ref,
            :health_probe_ref
          ],
          &Map.has_key?(map, &1)
        ),
        do: :ok,
        else: {:error, :missing_field}
      )

  @impl true
  def handle_call(:state, _from, state), do: {:reply, state.state, state}

  def handle_call({:transition, next}, _from, state) do
    if Chassis.Evolution.Core.Transitions.allowed?(state.state, next),
      do: {:reply, {:ok, next}, %{state | state: next}},
      else: {:reply, {:error, :illegal_transition}, state}
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
  def list, do: []
end
