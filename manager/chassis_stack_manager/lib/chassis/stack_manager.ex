defmodule Chassis.StackManager.FenceStore do
  @moduledoc """
  In-memory fence store for deployment idempotency.

  The stored fence uses `GroundPlane.Contracts.Fence` so the transaction path
  carries the lower-plane contract shape while remaining local and testable.
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

  @spec try_acquire(GenServer.server(), GroundPlane.Contracts.Fence.t(), String.t()) ::
          {:ok, GroundPlane.Contracts.Fence.t()}
          | {:completed, map()}
          | {:error, :already_held}
  def try_acquire(server, fence, key), do: GenServer.call(server, {:try_acquire, fence, key})

  @spec complete(GenServer.server(), String.t(), map()) :: :ok
  def complete(server, key, result), do: GenServer.call(server, {:complete, key, result})

  @spec release(GenServer.server(), String.t()) :: :ok
  def release(server, key), do: GenServer.call(server, {:release, key})

  @impl true
  def init(_opts), do: {:ok, %{held: %{}, completed: %{}}}

  @impl true
  def handle_call({:try_acquire, fence, key}, _from, state) do
    cond do
      Map.has_key?(state.completed, key) ->
        {:reply, {:completed, Map.fetch!(state.completed, key)}, state}

      Map.has_key?(state.held, key) ->
        {:reply, {:error, :already_held}, state}

      true ->
        {:reply, {:ok, fence}, %{state | held: Map.put(state.held, key, fence)}}
    end
  end

  def handle_call({:complete, key, result}, _from, state) do
    {:reply, :ok,
     %{
       state
       | held: Map.delete(state.held, key),
         completed: Map.put(state.completed, key, result)
     }}
  end

  def handle_call({:release, key}, _from, state) do
    {:reply, :ok, %{state | held: Map.delete(state.held, key)}}
  end
end

defmodule Chassis.StackManager.CheckpointStore do
  @moduledoc "In-memory checkpoint store for resumable rollback."

  use GenServer

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)

    case name do
      nil -> GenServer.start_link(__MODULE__, opts, [])
      _ -> GenServer.start_link(__MODULE__, opts, name: name)
    end
  end

  @spec fetch(GenServer.server(), String.t()) :: {:ok, map()} | {:error, :not_found}
  def fetch(server, checkpoint_ref), do: GenServer.call(server, {:fetch, checkpoint_ref})

  @spec complete(GenServer.server(), String.t(), GroundPlane.Contracts.Checkpoint.t()) :: :ok
  def complete(server, checkpoint_ref, checkpoint),
    do: GenServer.call(server, {:complete, checkpoint_ref, checkpoint})

  @spec fail(GenServer.server(), String.t(), term()) :: :ok
  def fail(server, checkpoint_ref, reason),
    do: GenServer.call(server, {:fail, checkpoint_ref, reason})

  @impl true
  def init(_opts), do: {:ok, %{}}

  @impl true
  def handle_call({:fetch, ref}, _from, state) do
    {:reply, Map.fetch(state, ref), state}
  end

  def handle_call({:complete, ref, checkpoint}, _from, state) do
    {:reply, :ok, Map.put(state, ref, %{status: :completed, checkpoint: checkpoint})}
  end

  def handle_call({:fail, ref, reason}, _from, state) do
    {:reply, :ok, Map.put(state, ref, %{status: :failed, reason: reason})}
  end
end

defmodule Chassis.StackManager.Transaction do
  @moduledoc """
  Deployment transaction orchestration.

  The transaction path is intentionally explicit: every side-effecting stage is
  represented by an injectable function in tests and a default implementation
  in development. Authority failure happens before provisioning, mesh join,
  registry writes, and receipt emission.
  """

  alias Chassis.AppRegistry
  alias Chassis.AppRegistry.Entry
  alias Chassis.Receipts.{DeploymentRecord, RollbackRecord, Store}
  alias Chassis.Stack.{Composer, ProfileResolver}
  alias Chassis.StackManager.{CheckpointStore, FenceStore}
  alias Chassis.Tenant.{Isolation, Quota, QuotaGuard, Residency, TopologyGuard}
  alias GroundPlane.Contracts.{Checkpoint, Fence}

  @steps [
    :fence_acquire,
    :resolve_profile,
    :discover_hosts,
    :validate_topology,
    :authorize,
    :provision,
    :mesh_join,
    :register_app,
    :emit_receipt
  ]

  @spec steps() :: [atom()]
  def steps, do: @steps

  @spec run(keyword() | map()) :: {:ok, map()} | {:error, term()}
  def run(attrs) do
    opts = normalize_opts(attrs)

    case require_tenant_context(opts) do
      :ok ->
        run_with_fence(opts)

      {:error, _reason} = error ->
        error
    end
  end

  defp run_with_fence(opts) do
    idempotency_key = Map.get(opts, :idempotency_key) || default_idempotency_key(opts)
    fence = build_fence(idempotency_key, opts)
    fence_store = Map.get(opts, :fence_store, FenceStore)

    case FenceStore.try_acquire(fence_store, fence, idempotency_key) do
      {:completed, result} ->
        {:ok, Map.put(result, :idempotent?, true)}

      {:error, :already_held} ->
        {:error, :idempotent_deployment_in_flight}

      {:ok, _fence} ->
        try do
          case do_run(opts, idempotency_key, fence) do
            {:ok, result} ->
              FenceStore.complete(fence_store, idempotency_key, result)
              {:ok, result}

            {:error, _reason} = error ->
              FenceStore.release(fence_store, idempotency_key)
              error
          end
        rescue
          error ->
            FenceStore.release(fence_store, idempotency_key)
            {:error, {:transaction_raised, Exception.message(error)}}
        end
    end
  end

  @spec rollback(String.t(), keyword() | map()) :: {:ok, map()} | {:error, term()}
  def rollback(app_ref, attrs \\ []) do
    opts = normalize_opts(attrs)
    registry = Map.fetch!(opts, :registry)
    receipts_store = Map.fetch!(opts, :receipts_store)
    checkpoint_store = Map.get(opts, :checkpoint_store, CheckpointStore)
    rollback_node = Map.get(opts, :rollback_node, fn _node -> :ok end)

    with {:ok, entry} <- AppRegistry.lookup(registry, app_ref),
         {:ok, rollback_target_ref} <- rollback_target(entry),
         {:ok, current_record} <-
           Store.Memory.get(receipts_store, entry.last_deployment_receipt_ref),
         {:ok, target_record} <- Store.Memory.get(receipts_store, rollback_target_ref),
         :ok <- rollback_nodes(entry.node_mesh, checkpoint_store, rollback_node),
         {:ok, rollback_record} <- emit_rollback(receipts_store, current_record, opts),
         :ok <-
           AppRegistry.update_status(registry, app_ref, :active,
             active_profile: target_record.profile_ref,
             last_deployment_receipt_ref: target_record.receipt_ref,
             rollback_target_ref: nil
           ) do
      {:ok,
       %{
         status: :rolled_back,
         app_ref: app_ref,
         rollback_target_ref: rollback_target_ref,
         rollback_receipt_ref: rollback_record.receipt_ref
       }}
    end
  end

  defp do_run(opts, idempotency_key, fence) do
    with {:ok, resolved} <- resolve_profile(opts),
         {:ok, hosts} <- discover_hosts(opts),
         {:ok, quota} <- tenant_quota(opts),
         :ok <- validate_tenant_topology(opts, resolved, hosts, quota),
         :ok <- check_tenant_quota(opts, resolved, quota),
         {:ok, topology} <- Composer.compose(resolved.profile_ref, resolved.env, hosts),
         {:ok, authority_ref} <- authorize(opts, topology),
         {:ok, _provision_result} <- provision(opts, topology),
         {:ok, node_mesh} <- mesh_join(opts, topology),
         receipt_ref = Chassis.Receipts.new_ref("receipt:deployment"),
         {:ok, entry} <- register_app(opts, topology, node_mesh, receipt_ref),
         {:ok, receipt} <- emit_deployment(opts, entry, authority_ref, receipt_ref) do
      {:ok,
       %{
         status: :active,
         steps: @steps,
         receipt_ref: receipt.receipt_ref,
         app_ref: entry.app_ref,
         node_mesh: node_mesh,
         authority_ref: authority_ref,
         fence_ref: fence.resource,
         idempotency_key: idempotency_key,
         idempotent?: false
       }}
    end
  end

  defp resolve_profile(opts) do
    profile_ref = Map.fetch!(opts, :profile_ref)
    env = Map.get(opts, :env, :dev)
    ProfileResolver.resolve(profile_ref, env)
  end

  defp require_tenant_context(opts) do
    missing =
      [:tenant_ref, :installation_ref]
      |> Enum.reject(fn field ->
        case Map.get(opts, field) do
          value when is_binary(value) and value != "" -> true
          _ -> false
        end
      end)

    case missing do
      [] -> :ok
      fields -> {:error, {:tenant_context_required, fields}}
    end
  end

  defp validate_tenant_topology(opts, resolved, hosts, quota) do
    with {:ok, residency} <- tenant_residency(opts),
         {:ok, isolation} <- tenant_isolation(opts),
         {:ok, result} <-
           TopologyGuard.validate(%{
             profile: resolved,
             tenant_ref: Map.get(opts, :tenant_ref),
             installation_ref: Map.get(opts, :installation_ref),
             residency_contract: residency,
             isolation_profile: isolation,
             resource_quota: quota,
             hosts: hosts,
             authority_ref: Map.get(opts, :authority_ref),
             trace_id: Map.get(opts, :trace_id)
           }) do
      if result.valid?, do: :ok, else: {:error, {:topology_invalid, result.errors}}
    end
  end

  defp check_tenant_quota(opts, resolved, quota) do
    requested = Map.get(opts, :requested_resources, TopologyGuard.required_resources(resolved))

    case QuotaGuard.check(quota, requested) do
      {:ok, %{allowed?: true}} -> :ok
      {:ok, %{allowed?: false} = decision} -> {:error, {:quota_exceeded, decision}}
    end
  end

  defp tenant_residency(opts),
    do: Residency.Catalog.fetch(Map.get(opts, :residency_ref, "residency:global"))

  defp tenant_isolation(opts),
    do: Isolation.Catalog.fetch(Map.get(opts, :isolation_profile_ref, "isolation:dev-shared"))

  defp tenant_quota(opts) do
    with {:ok, quota} <- Quota.Catalog.fetch(Map.get(opts, :quota_ref, "quota:tenant:enterprise")) do
      {:ok, %{quota | tenant_ref: Map.get(opts, :tenant_ref)}}
    end
  end

  defp discover_hosts(%{discover_hosts: fun}) when is_function(fun, 0), do: fun.()
  defp discover_hosts(%{hosts: hosts}) when is_list(hosts), do: {:ok, hosts}
  defp discover_hosts(%{env: :dev}), do: {:ok, Chassis.Inventory.fixture_hosts()}
  defp discover_hosts(_opts), do: {:error, :missing_host_discovery}

  defp authorize(%{authorize: fun} = opts, topology) when is_function(fun, 1) do
    opts
    |> Map.take([:profile_ref, :env, :app_atom, :tenant_ref, :installation_ref])
    |> Map.put(:topology_ref, topology.topology_ref)
    |> fun.()
    |> normalize_authority()
  end

  defp authorize(_opts, _topology), do: {:ok, "authority:dev:implicit"}

  defp normalize_authority({:ok, ref}) when is_binary(ref), do: {:ok, ref}
  defp normalize_authority({:error, reason}), do: {:error, reason}
  defp normalize_authority(other), do: {:error, {:invalid_authority_result, other}}

  defp provision(%{provision: fun}, topology) when is_function(fun, 1), do: fun.(topology)
  defp provision(%{env: :dev}, _topology), do: {:ok, :local_noop}
  defp provision(_opts, _topology), do: {:error, :missing_provisioner}

  defp mesh_join(%{mesh_join: fun}, topology) when is_function(fun, 1), do: fun.(topology)
  defp mesh_join(%{env: :dev}, _topology), do: {:ok, [node()]}
  defp mesh_join(_opts, _topology), do: {:error, :missing_mesh_joiner}

  defp register_app(opts, topology, node_mesh, receipt_ref) do
    registry = Map.fetch!(opts, :registry)

    entry =
      Entry.new!(%{
        app_ref: app_ref(opts),
        app_atom: Map.fetch!(opts, :app_atom),
        installation_ref: Map.fetch!(opts, :installation_ref),
        tenant_ref: Map.fetch!(opts, :tenant_ref),
        active_profile: topology.profile_ref,
        environment: topology.env,
        git_sha: Map.get(opts, :git_sha, "unknown"),
        release_version: Map.get(opts, :release_version, "unknown"),
        node_mesh: node_mesh,
        status: :active,
        last_deployment_receipt_ref: receipt_ref
      })

    AppRegistry.register(registry, entry)
  end

  defp emit_deployment(opts, %Entry{} = entry, authority_ref, receipt_ref) do
    receipts_store = Map.fetch!(opts, :receipts_store)

    record = %DeploymentRecord{
      receipt_ref: receipt_ref,
      app_ref: entry.app_ref,
      profile_ref: entry.active_profile,
      env: entry.environment,
      status: :active,
      authority_ref: authority_ref,
      tenant_ref: entry.tenant_ref,
      labels: %{
        app_atom: Atom.to_string(entry.app_atom),
        release_version: entry.release_version,
        git_sha: entry.git_sha,
        node_mesh: Enum.map(entry.node_mesh, &Atom.to_string/1)
      }
    }

    Store.Memory.put(receipts_store, record)
  end

  defp rollback_target(%Entry{rollback_target_ref: ref}) when is_binary(ref), do: {:ok, ref}
  defp rollback_target(%Entry{}), do: {:error, :no_rollback_target}

  defp rollback_nodes(nodes, checkpoint_store, rollback_node) do
    nodes
    |> Enum.with_index(1)
    |> Enum.reduce_while(:ok, fn {node, idx}, :ok ->
      checkpoint_ref = "ck:chassis.rollback:#{Atom.to_string(node)}"

      case CheckpointStore.fetch(checkpoint_store, checkpoint_ref) do
        {:ok, %{status: :completed}} ->
          {:cont, :ok}

        _ ->
          checkpoint =
            new_checkpoint!(%{
              stream: checkpoint_ref,
              position: idx,
              reason: "rollback #{Atom.to_string(node)}"
            })

          case rollback_node.(node) do
            :ok ->
              CheckpointStore.complete(checkpoint_store, checkpoint_ref, checkpoint)
              {:cont, :ok}

            {:error, reason} ->
              CheckpointStore.fail(checkpoint_store, checkpoint_ref, reason)
              {:halt, {:error, {:node_rollback_failed, node, reason}}}
          end
      end
    end)
  end

  defp emit_rollback(receipts_store, %DeploymentRecord{} = current, opts) do
    record = %RollbackRecord{
      receipt_ref: Chassis.Receipts.new_ref("receipt:rollback"),
      deployment_receipt_ref: current.receipt_ref,
      trigger: Map.get(opts, :trigger, :operator),
      status: :rolled_back,
      authority_ref: Map.get(opts, :authority_ref)
    }

    Store.Memory.put(receipts_store, record)
  end

  defp build_fence(idempotency_key, opts) do
    %Fence{
      resource: "fence:chassis.deploy:" <> idempotency_key,
      holder: "chassis.stack_manager",
      lease_id: idempotency_key,
      epoch: 1,
      tenant_id: Map.get(opts, :tenant_ref),
      operation_class: "materialize_deployment",
      target_ref: app_ref(opts),
      fence_token: fence_token(idempotency_key),
      persistence_posture: %{mode: :memory, owner: :chassis_stack_manager}
    }
  end

  defp app_ref(opts) do
    "app:" <>
      Atom.to_string(Map.fetch!(opts, :app_atom)) <>
      ":" <> Map.fetch!(opts, :installation_ref) <> ":" <> Map.fetch!(opts, :tenant_ref)
  end

  defp default_idempotency_key(opts) do
    payload = {Map.get(opts, :profile_ref), Map.get(opts, :env), Map.get(opts, :app_atom)}
    :crypto.hash(:sha256, :erlang.term_to_binary(payload)) |> Base.encode16(case: :lower)
  end

  defp fence_token(key), do: :crypto.hash(:sha256, key) |> Base.encode16(case: :lower)
  defp normalize_opts(opts) when is_map(opts), do: opts
  defp normalize_opts(opts) when is_list(opts), do: Map.new(opts)

  defp new_checkpoint!(attrs) do
    case Checkpoint.new(attrs) do
      {:ok, checkpoint} -> checkpoint
      {:error, reason} -> raise ArgumentError, "invalid checkpoint: #{inspect(reason)}"
    end
  end
end
