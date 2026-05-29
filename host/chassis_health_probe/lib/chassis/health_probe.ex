defmodule Chassis.Health.Probe do
  @moduledoc "Health probe window."
  @checks [
    :http_health,
    :beam_alive,
    :mesh_connectivity,
    :appkit_readback,
    :mezzanine_heartbeat,
    :citadel_smoke,
    :state_heartbeat,
    :model_runtime_health
  ]
  def run(attrs, opts \\ []) do
    forced = Keyword.get(opts, :force, :success)
    outcome = if forced == :failure, do: :rolled_back, else: :committed

    {:ok,
     %{swap_ref: Map.get(attrs, :swap_ref, "swap:dev:smoke"), outcome: outcome, checks: @checks}}
  end
end

defmodule Chassis.Health.Probe.Supervisor do
  @moduledoc "Probe supervisor."
  use Supervisor
  def start_link(opts \\ []), do: Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  @impl true
  def init(_opts), do: Supervisor.init([], strategy: :one_for_one)
end

defmodule Chassis.Health.Probe.Registry do
  @moduledoc "Probe registry."
  def list, do: []
end
