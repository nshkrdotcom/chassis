defmodule Chassis.Health.Probe do
  @moduledoc """
  Post-swap health probe and rollback dispatcher.

  `run/2` is the synchronous engine used by tests, smoke commands, and the
  GenServer facade. Time is modeled by policy ticks so tests do not sleep for the
  default 90-second window.
  """

  use GenServer

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

  @check_modules %{
    http_health: Chassis.Health.Probe.Check.HTTPHealth,
    beam_alive: Chassis.Health.Probe.Check.BEAMAlive,
    mesh_connectivity: Chassis.Health.Probe.Check.MeshConnectivity,
    appkit_readback: Chassis.Health.Probe.Check.AppKitReadback,
    mezzanine_heartbeat: Chassis.Health.Probe.Check.MezzanineHeartbeat,
    citadel_smoke: Chassis.Health.Probe.Check.CitadelSmoke,
    state_heartbeat: Chassis.Health.Probe.Check.StateHeartbeat,
    model_runtime_health: Chassis.Health.Probe.Check.ModelRuntimeHealth
  }

  @type policy :: %{
          window_ms: pos_integer(),
          interval_ms: pos_integer(),
          consecutive_required: pos_integer(),
          rollback_on_failure?: boolean(),
          checks: [atom()]
        }

  @type result :: {:ok, map()} | {:error, term()}

  @spec default_policy() :: policy()
  def default_policy do
    %{
      window_ms: 90_000,
      interval_ms: 5_000,
      consecutive_required: 3,
      rollback_on_failure?: true,
      checks: @checks
    }
  end

  @spec run(map(), keyword()) :: result()
  def run(attrs, opts \\ []) when is_map(attrs) do
    with {:ok, context} <- context(attrs, opts),
         {:ok, policy} <- policy(opts) do
      max_ticks = max(1, div(policy.window_ms, policy.interval_ms))
      do_run(context, policy, opts, max_ticks, 0, 0)
    end
  end

  @spec start_link(map()) :: GenServer.on_start()
  def start_link(%{swap_ref: swap_ref} = arg) when is_binary(swap_ref) do
    GenServer.start_link(__MODULE__, arg, name: Chassis.Health.Probe.Registry.via(swap_ref))
  end

  @spec result(String.t()) :: {:committed | :probing | :rolled_back | :rolled_back_failed, map()}
  def result(swap_ref) when is_binary(swap_ref) do
    GenServer.call(Chassis.Health.Probe.Registry.via(swap_ref), :result)
  end

  @impl true
  def init(arg) do
    opts = Map.get(arg, :opts, [])

    {:ok,
     %{
       swap_ref: arg.swap_ref,
       attrs: Map.delete(arg, :opts),
       opts: opts,
       status: :probing,
       result: %{swap_ref: arg.swap_ref, outcome: :probing}
     }, {:continue, :run}}
  end

  @impl true
  def handle_continue(:run, state) do
    {:ok, result} = run(state.attrs, state.opts)
    {:noreply, %{state | status: result.outcome, result: result}}
  end

  @impl true
  def handle_call(:result, _from, state), do: {:reply, {state.status, state.result}, state}

  defp do_run(context, policy, opts, _max_ticks, ticks, consecutive_successes)
       when consecutive_successes >= policy.consecutive_required do
    commit(context, policy, ticks, consecutive_successes, opts)
  end

  defp do_run(context, policy, opts, max_ticks, ticks, consecutive_successes)
       when ticks >= max_ticks do
    rollback(context, policy, opts, :probe_timeout, ticks, consecutive_successes)
  end

  defp do_run(context, policy, opts, max_ticks, ticks, consecutive_successes) do
    case run_tick(context, policy, opts) do
      :ok ->
        next_successes = consecutive_successes + 1
        next_ticks = ticks + 1

        if next_successes >= policy.consecutive_required do
          commit(context, policy, next_ticks, next_successes, opts)
        else
          sleep(policy, opts)
          do_run(context, policy, opts, max_ticks, next_ticks, next_successes)
        end

      {:error, reason} ->
        rollback(context, policy, opts, reason, ticks + 1, consecutive_successes)
    end
  end

  defp run_tick(context, policy, opts) do
    Enum.reduce_while(policy.checks, :ok, fn check, :ok ->
      case run_check(check, context, opts) do
        :ok ->
          {:cont, :ok}

        {:ok, _metadata} ->
          {:cont, :ok}

        {:error, reason} ->
          {:halt, {:error, {:probe_failed, check, reason}}}

        other ->
          {:halt, {:error, {:invalid_check_result, check, other}}}
      end
    end)
  end

  defp run_check(check, context, opts) do
    case Map.fetch(@check_modules, check) do
      {:ok, module} -> module.run(context, opts)
      :error -> {:error, {:unknown_check, check}}
    end
  end

  defp commit(context, policy, ticks, consecutive_successes, opts) do
    maybe_emit_trace(:committed, context, opts)

    {:ok,
     %{
       swap_ref: context.swap_ref,
       outcome: :committed,
       checks: policy.checks,
       ticks: ticks,
       consecutive_successes: consecutive_successes
     }}
  end

  defp rollback(context, policy, opts, reason, ticks, consecutive_successes) do
    if policy.rollback_on_failure? do
      rollback = call_rollback(context, reason, opts)

      case rollback do
        {:ok, _rollback_result} ->
          maybe_emit_trace(:rolled_back, context, opts)

          {:ok,
           %{
             swap_ref: context.swap_ref,
             outcome: :rolled_back,
             reason: reason,
             rollback: rollback,
             checks: policy.checks,
             ticks: ticks,
             consecutive_successes: consecutive_successes
           }}

        {:error, _rollback_reason} ->
          health_signal = emit_critical_rollback_signal(context, reason, rollback, opts)

          {:ok,
           %{
             swap_ref: context.swap_ref,
             outcome: :rolled_back_failed,
             reason: reason,
             rollback: rollback,
             health_signal: health_signal,
             checks: policy.checks,
             ticks: ticks,
             consecutive_successes: consecutive_successes
           }}
      end
    else
      {:ok,
       %{
         swap_ref: context.swap_ref,
         outcome: :failed,
         reason: reason,
         checks: policy.checks,
         ticks: ticks,
         consecutive_successes: consecutive_successes
       }}
    end
  end

  defp call_rollback(context, reason, opts) do
    rollback_fun = Keyword.get(opts, :rollback_fun, &Chassis.Swap.Supervisor.rollback_swap/2)

    rollback_opts =
      [
        restored_artifact_digest: context.prior_artifact_digest,
        reason_code: reason,
        service_ref: context.service_ref
      ]
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)

    rollback_fun.(context.swap_ref, rollback_opts)
  end

  defp emit_critical_rollback_signal(context, reason, rollback, opts) do
    signal = %{
      component_ref: "component:chassis_health_probe",
      service_ref: context.service_ref,
      status: :critical,
      reason: :rollback_failed,
      trace_id: context.trace_id,
      metadata: %{
        severity: :critical,
        kind: :rollback_failed,
        swap_ref: context.swap_ref,
        rollback_reason: inspect(reason),
        rollback_result: inspect(rollback)
      }
    }

    Chassis.Metrics.emit_health_signal(signal, backend: Keyword.get(opts, :metrics_backend))
    signal
  end

  defp maybe_emit_trace(outcome, context, opts) do
    case Keyword.get(opts, :trace_fun) do
      nil ->
        :ok

      trace_fun when is_function(trace_fun, 2) ->
        trace_fun.(outcome, context)
    end
  end

  defp context(attrs, opts) do
    swap_ref = read(attrs, :swap_ref) || Keyword.get(opts, :swap_ref)

    if present?(swap_ref) do
      {:ok,
       %{
         swap_ref: swap_ref,
         service_ref: read(attrs, :service_ref) || "service:#{swap_ref}",
         trace_id: read(attrs, :trace_id) || "trace:#{swap_ref}",
         prior_artifact_digest: read(attrs, :prior_artifact_digest)
       }}
    else
      {:error, {:missing_required, :swap_ref}}
    end
  end

  defp policy(opts) do
    policy =
      default_policy()
      |> Map.merge(Keyword.get(opts, :policy, %{}))
      |> maybe_put(:window_ms, Keyword.get(opts, :window_ms))
      |> maybe_put(:interval_ms, Keyword.get(opts, :interval_ms))
      |> maybe_put(:consecutive_required, Keyword.get(opts, :consecutive_required))
      |> maybe_put(:rollback_on_failure?, Keyword.get(opts, :rollback_on_failure?))
      |> maybe_put(:checks, Keyword.get(opts, :checks))

    with :ok <- positive_integer(policy.window_ms, :window_ms),
         :ok <- positive_integer(policy.interval_ms, :interval_ms),
         :ok <- positive_integer(policy.consecutive_required, :consecutive_required),
         :ok <- check_list(policy.checks) do
      {:ok, policy}
    end
  end

  defp sleep(policy, opts),
    do: Keyword.get(opts, :sleep_fun, fn _ms -> :ok end).(policy.interval_ms)

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp positive_integer(value, _field) when is_integer(value) and value > 0, do: :ok
  defp positive_integer(value, field), do: {:error, {:invalid_policy, field, value}}

  defp check_list(checks) when is_list(checks), do: :ok
  defp check_list(checks), do: {:error, {:invalid_policy, :checks, checks}}

  defp read(map, field) do
    Map.get(map, field) || Map.get(map, Atom.to_string(field))
  end

  defp present?(nil), do: false
  defp present?(""), do: false
  defp present?(_value), do: true
end

defmodule Chassis.Health.Probe.CheckRunner do
  @moduledoc false

  @spec run(atom(), map(), keyword()) :: :ok | {:ok, map()} | {:error, term()}
  def run(check, context, opts) do
    case Keyword.get(opts, :check_fun) do
      fun when is_function(fun, 2) ->
        fun.(check, context)

      nil ->
        default_result(check, context, opts)
    end
  end

  defp default_result(check, context, opts) do
    failures =
      Keyword.get(opts, :check_failures, %{})
      |> Map.merge(Map.get(context, :check_failures, %{}))

    results = Keyword.get(opts, :check_results, %{})

    cond do
      Map.has_key?(failures, check) -> {:error, Map.fetch!(failures, check)}
      Map.has_key?(results, check) -> Map.fetch!(results, check)
      true -> :ok
    end
  end
end

defmodule Chassis.Health.Probe.Check.HTTPHealth do
  @moduledoc "HTTP health endpoint check."
  def run(context, opts), do: Chassis.Health.Probe.CheckRunner.run(:http_health, context, opts)
end

defmodule Chassis.Health.Probe.Check.BEAMAlive do
  @moduledoc "BEAM liveness check."
  def run(context, opts), do: Chassis.Health.Probe.CheckRunner.run(:beam_alive, context, opts)
end

defmodule Chassis.Health.Probe.Check.MeshConnectivity do
  @moduledoc "Mesh connectivity check."
  def run(context, opts),
    do: Chassis.Health.Probe.CheckRunner.run(:mesh_connectivity, context, opts)
end

defmodule Chassis.Health.Probe.Check.AppKitReadback do
  @moduledoc "AppKit readback health check."
  def run(context, opts),
    do: Chassis.Health.Probe.CheckRunner.run(:appkit_readback, context, opts)
end

defmodule Chassis.Health.Probe.Check.MezzanineHeartbeat do
  @moduledoc "Mezzanine heartbeat lag check."
  def run(context, opts),
    do: Chassis.Health.Probe.CheckRunner.run(:mezzanine_heartbeat, context, opts)
end

defmodule Chassis.Health.Probe.Check.CitadelSmoke do
  @moduledoc "Citadel smoke check."
  def run(context, opts), do: Chassis.Health.Probe.CheckRunner.run(:citadel_smoke, context, opts)
end

defmodule Chassis.Health.Probe.Check.StateHeartbeat do
  @moduledoc "Durable state heartbeat check."
  def run(context, opts),
    do: Chassis.Health.Probe.CheckRunner.run(:state_heartbeat, context, opts)
end

defmodule Chassis.Health.Probe.Check.ModelRuntimeHealth do
  @moduledoc "Model runtime health check."
  def run(context, opts),
    do: Chassis.Health.Probe.CheckRunner.run(:model_runtime_health, context, opts)
end

defmodule Chassis.Health.Probe.Supervisor do
  @moduledoc "Supervisor for health probe registry state."

  use Supervisor

  def start_link(opts \\ []), do: Supervisor.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    Supervisor.init([Chassis.Health.Probe.Registry], strategy: :one_for_one)
  end
end

defmodule Chassis.Health.Probe.Registry do
  @moduledoc "Registry wrapper for active probe processes."

  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(_opts) do
    Registry.child_spec(keys: :unique, name: __MODULE__)
  end

  @spec via(String.t()) :: {:via, Registry, {module(), String.t()}}
  def via(ref), do: {:via, Registry, {__MODULE__, ref}}

  @spec list() :: [String.t()]
  def list do
    if Process.whereis(__MODULE__) do
      Registry.select(__MODULE__, [{{:"$1", :_, :_}, [], [:"$1"]}])
    else
      []
    end
  end
end
