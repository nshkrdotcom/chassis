defmodule Chassis.Swap.Supervisor do
  @moduledoc """
  State-preserving promotion swap executor.

  The public `execute_swap/2` path is deliberately adapter-driven: the package
  owns preflight, mount allowlist validation, ordering, idempotency, and rollback
  orchestration while callers provide the host runtime side effects.
  """

  use DynamicSupervisor

  @behaviour Chassis.Evolution.PromotionExecutor

  alias Chassis.Evolution.PromotionPreconditions
  alias Chassis.Swap.Supervisor.IdempotencyTable

  @default_probe_window_ms 90_000

  @spec start_link(term()) :: Supervisor.on_start()
  def start_link(_arg), do: DynamicSupervisor.start_link(__MODULE__, :ok, name: __MODULE__)

  @impl true
  def init(:ok), do: DynamicSupervisor.init(strategy: :one_for_one)

  @spec start_swap(PromotionPreconditions.t() | map(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def start_swap(preconditions, opts \\ []), do: execute_swap(preconditions, opts)

  @impl Chassis.Evolution.PromotionExecutor
  def execute_swap(preconditions, opts \\ []) do
    with {:ok, preconditions} <- normalize_preconditions(preconditions),
         :ok <- ensure_regression_passed(preconditions),
         {:ok, mounts_used} <- validate_mounts(preconditions, opts),
         {:ok, new_artifact_digest} <- resolve_artifact(preconditions, opts),
         {:ok, swap_ref} <- resolve_swap_ref(preconditions, opts) do
      table = idempotency_table(opts)

      IdempotencyTable.execute(table, swap_ref, fn ->
        run_swap(preconditions, swap_ref, new_artifact_digest, mounts_used, opts)
      end)
    end
  end

  @spec promote(PromotionPreconditions.t() | map(), keyword()) :: {:ok, map()} | {:error, term()}
  def promote(preconditions, opts \\ []), do: execute_swap(preconditions, opts)

  @impl Chassis.Evolution.PromotionExecutor
  def rollback_swap(swap_ref, opts \\ [])

  def rollback_swap(swap_ref, opts) when is_binary(swap_ref) do
    restored_artifact_digest =
      Keyword.get(opts, :restored_artifact_digest) ||
        Keyword.get(opts, :prior_artifact_digest)

    if present?(restored_artifact_digest) do
      rollback_ref = Keyword.get(opts, :rollback_ref, "rollback:#{swap_ref}")

      context = %{
        rollback_ref: rollback_ref,
        swap_ref: swap_ref,
        restored_artifact_digest: restored_artifact_digest,
        reason_code: Keyword.get(opts, :reason_code, :operator_requested)
      }

      with :ok <- normalize_unit_result(call_rollback(context, opts)) do
        {:ok,
         %{
           rollback_ref: rollback_ref,
           swap_ref: swap_ref,
           restored_artifact_digest: restored_artifact_digest
         }}
      end
    else
      {:error, {:missing_required, :restored_artifact_digest}}
    end
  end

  def rollback_swap(_swap_ref, _opts), do: {:error, {:invalid_field, :swap_ref}}

  @spec rollback(map() | String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def rollback(request, opts \\ [])

  def rollback(%{swap_ref: swap_ref} = request, opts) do
    opts =
      opts
      |> Keyword.put(:restored_artifact_digest, Map.get(request, :restored_artifact_digest))
      |> Keyword.put(:reason_code, Map.get(request, :reason_code, :operator_requested))

    rollback_swap(swap_ref, opts)
  end

  def rollback(swap_ref, opts), do: rollback_swap(swap_ref, opts)

  @spec start_swap_task(PromotionPreconditions.t() | map(), keyword()) ::
          DynamicSupervisor.on_start_child()
  def start_swap_task(preconditions, opts \\ []) do
    DynamicSupervisor.start_child(__MODULE__, {Task, fn -> execute_swap(preconditions, opts) end})
  end

  @spec smoke_preconditions(String.t()) :: map()
  def smoke_preconditions(candidate_ref) when is_binary(candidate_ref) do
    %{
      candidate_ref: candidate_ref,
      failure_batch_ref: "failure:smoke",
      patch_digest: "sha256:patch-smoke",
      artifact_digest: "sha256:candidate-smoke",
      score_matrix_ref: "score:smoke",
      regression_gate: :passed,
      authority_ref: "authority:smoke",
      operator_consent_ref: "consent:smoke",
      rollback_ref: "rollback:smoke",
      target_installation_ref: "installation:smoke",
      approved_state_volume_mounts: ["/var/lib/nshkr/state"],
      trace_id: "trace:smoke"
    }
  end

  @spec smoke_opts(keyword()) :: keyword()
  def smoke_opts(opts \\ []) do
    candidate_ref = Keyword.get(opts, :candidate_ref, "cand:dev:smoke")

    [
      swap_ref: Keyword.get(opts, :swap_ref, "swap:#{candidate_ref}"),
      app_ref: Keyword.get(opts, :app_ref, "app:smoke"),
      profile_ref: Keyword.get(opts, :profile_ref, "prod"),
      current_artifact_fun: fn _target_installation_ref -> {:ok, "sha256:prior-smoke"} end,
      stop_fun: fn _target_installation_ref -> :ok end,
      switch_fun: fn _context -> :ok end,
      start_fun: fn _target_installation_ref -> :ok end,
      rollback_fun: fn _context -> :ok end
    ]
  end

  defp normalize_preconditions(%PromotionPreconditions{} = preconditions) do
    preconditions
    |> Map.from_struct()
    |> require_precondition_fields()
    |> case do
      :ok -> {:ok, preconditions}
      error -> error
    end
  end

  defp normalize_preconditions(%{} = attrs) do
    with :ok <- require_precondition_fields(attrs) do
      {:ok, PromotionPreconditions.new!(attrs)}
    end
  rescue
    exception in ArgumentError -> {:error, {:invalid_preconditions, Exception.message(exception)}}
  end

  defp normalize_preconditions(_preconditions), do: {:error, {:invalid_field, :preconditions}}

  defp require_precondition_fields(attrs) when is_map(attrs) do
    case Enum.find(PromotionPreconditions.required_fields(), &(not present?(read(attrs, &1)))) do
      nil -> :ok
      field -> {:error, {:missing_required, field}}
    end
  end

  defp ensure_regression_passed(%PromotionPreconditions{regression_gate: :passed}), do: :ok

  defp ensure_regression_passed(%PromotionPreconditions{regression_gate: gate}),
    do: {:error, {:regression_gate_not_passed, gate}}

  defp validate_mounts(%PromotionPreconditions{} = preconditions, opts) do
    with {:ok, allowed_mounts} <- allowed_mounts(opts) do
      preconditions.approved_state_volume_mounts
      |> List.wrap()
      |> Enum.reduce_while({:ok, []}, fn requested, {:ok, mounts} ->
        path = mount_path(requested)

        case Map.fetch(allowed_mounts, path) do
          {:ok, %{kind: :mutable_state} = mount} ->
            {:cont, {:ok, mounts ++ [mount]}}

          {:ok, %{kind: kind}} ->
            {:halt, {:error, {:mount_kind_mismatch, path, kind}}}

          :error ->
            {:halt, {:error, {:unapproved_mount_path, path}}}
        end
      end)
    end
  end

  defp allowed_mounts(opts) do
    result =
      opts
      |> Keyword.get(:approved_mounts_fun, &Chassis.Releases.ApprovedMounts.list/2)
      |> then(fn fun ->
        fun.(Keyword.get(opts, :app_ref, "app:default"), Keyword.get(opts, :profile_ref, "prod"))
      end)

    normalize_mount_allowlist(result)
  end

  defp normalize_mount_allowlist(result) when is_list(result) do
    Enum.reduce_while(result, {:ok, %{}}, fn raw_mount, {:ok, acc} ->
      case normalize_mount(raw_mount) do
        {:ok, mount} -> {:cont, {:ok, Map.put(acc, mount.path, mount)}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp normalize_mount_allowlist(result), do: {:error, {:invalid_mount_allowlist, result}}

  defp resolve_artifact(%PromotionPreconditions{artifact_digest: artifact_digest}, opts) do
    resolver = Keyword.get(opts, :artifact_resolver_fun, &default_artifact_resolver/2)
    resolver.(artifact_digest, opts)
  end

  defp default_artifact_resolver(artifact_digest, _opts) when is_binary(artifact_digest) do
    if present?(artifact_digest),
      do: {:ok, artifact_digest},
      else: {:error, {:missing_required, :artifact_digest}}
  end

  defp default_artifact_resolver(_artifact_digest, _opts),
    do: {:error, {:invalid_field, :artifact_digest}}

  defp resolve_swap_ref(%PromotionPreconditions{} = preconditions, opts) do
    case Keyword.get(opts, :swap_ref) do
      swap_ref when is_binary(swap_ref) and byte_size(swap_ref) > 0 ->
        {:ok, swap_ref}

      nil ->
        {:ok,
         "swap:" <>
           short_hash(
             [
               preconditions.candidate_ref,
               preconditions.target_installation_ref,
               preconditions.artifact_digest
             ]
             |> Enum.join(":")
           )}

      _other ->
        {:error, {:invalid_field, :swap_ref}}
    end
  end

  defp run_swap(preconditions, swap_ref, new_artifact_digest, mounts_used, opts) do
    target = preconditions.target_installation_ref

    case current_artifact(target, opts) do
      {:ok, prior_artifact_digest} ->
        stop_at = now(opts)

        case run_host_transition(preconditions, swap_ref, new_artifact_digest, mounts_used, opts) do
          :ok ->
            start_at = now(opts)

            {:ok,
             %{
               swap_ref: swap_ref,
               candidate_ref: preconditions.candidate_ref,
               target_installation_ref: target,
               prior_artifact_digest: prior_artifact_digest,
               previous_artifact_digest: prior_artifact_digest,
               new_artifact_digest: new_artifact_digest,
               artifact_digest: new_artifact_digest,
               mounts_used: mounts_used,
               health_probe_window_ms:
                 Keyword.get(opts, :health_probe_window_ms, @default_probe_window_ms),
               stop_at: stop_at,
               start_at: start_at,
               swapped_at: start_at,
               trace_id: preconditions.trace_id
             }}

          {:error, reason} ->
            rollback = rollback_swap(swap_ref, rollback_opts(opts, prior_artifact_digest, reason))
            {:error, {:swap_failed, reason, rollback: rollback}}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp run_host_transition(preconditions, swap_ref, new_artifact_digest, mounts_used, opts) do
    context = %{
      swap_ref: swap_ref,
      candidate_ref: preconditions.candidate_ref,
      target_installation_ref: preconditions.target_installation_ref,
      new_artifact_digest: new_artifact_digest,
      mounts_used: mounts_used,
      trace_id: preconditions.trace_id
    }

    with :ok <-
           normalize_unit_result(
             call_side_effect(:stop_fun, preconditions.target_installation_ref, opts)
           ),
         :ok <- normalize_unit_result(call_side_effect(:switch_fun, context, opts)),
         :ok <-
           normalize_unit_result(
             call_side_effect(:start_fun, preconditions.target_installation_ref, opts)
           ) do
      :ok
    end
  end

  defp current_artifact(target_installation_ref, opts) do
    opts
    |> Keyword.get(:current_artifact_fun, fn _target ->
      {:error, {:missing_runtime_adapter, :current_artifact}}
    end)
    |> then(fn fun -> fun.(target_installation_ref) end)
    |> case do
      {:ok, digest} when is_binary(digest) and byte_size(digest) > 0 -> {:ok, digest}
      {:ok, digest} -> {:error, {:invalid_prior_artifact_digest, digest}}
      {:error, reason} -> {:error, reason}
      other -> {:error, {:invalid_runtime_result, :current_artifact, other}}
    end
  end

  defp call_side_effect(name, argument, opts) do
    default = fn _argument -> {:error, {:missing_runtime_adapter, name}} end
    Keyword.get(opts, name, default).(argument)
  end

  defp call_rollback(context, opts) do
    Keyword.get(opts, :rollback_fun, fn _context -> :ok end).(context)
  end

  defp normalize_unit_result(:ok), do: :ok
  defp normalize_unit_result({:ok, _value}), do: :ok
  defp normalize_unit_result({:error, reason}), do: {:error, reason}
  defp normalize_unit_result(other), do: {:error, {:invalid_runtime_result, other}}

  defp rollback_opts(opts, prior_artifact_digest, reason) do
    opts
    |> Keyword.put(:restored_artifact_digest, prior_artifact_digest)
    |> Keyword.put(:reason_code, reason)
  end

  defp idempotency_table(opts) do
    case Keyword.fetch(opts, :idempotency_table) do
      {:ok, table} ->
        table

      :error ->
        ensure_default_idempotency_table()
    end
  end

  defp ensure_default_idempotency_table do
    case Process.whereis(IdempotencyTable) do
      nil ->
        case IdempotencyTable.start_link(name: IdempotencyTable) do
          {:ok, pid} -> pid
          {:error, {:already_started, pid}} -> pid
        end

      pid ->
        pid
    end
  end

  defp normalize_mount(%{} = mount) do
    path = read(mount, :path)

    if present?(path) do
      {:ok,
       %{
         path: path,
         kind: normalize_mount_kind(read(mount, :kind)),
         mode: normalize_mount_mode(read(mount, :mode) || :rw)
       }}
    else
      {:error, {:invalid_mount_allowlist_entry, mount}}
    end
  end

  defp normalize_mount(mount), do: {:error, {:invalid_mount_allowlist_entry, mount}}

  defp mount_path(path) when is_binary(path), do: path
  defp mount_path(%{} = mount), do: read(mount, :path)

  defp normalize_mount_kind("mutable_state"), do: :mutable_state
  defp normalize_mount_kind(kind), do: kind

  defp normalize_mount_mode("rw"), do: :rw
  defp normalize_mount_mode("ro"), do: :ro
  defp normalize_mount_mode(mode), do: mode

  defp now(opts), do: Keyword.get(opts, :now_fun, &DateTime.utc_now/0).()

  defp read(map, field) when is_atom(field) do
    Map.get(map, field) || Map.get(map, Atom.to_string(field))
  end

  defp present?(value), do: not is_nil(value) and value != ""

  defp short_hash(value) do
    :crypto.hash(:sha256, value)
    |> Base.encode16(case: :lower)
    |> binary_part(0, 16)
  end
end

defmodule Chassis.Swap.Supervisor.IdempotencyTable do
  @moduledoc "In-memory idempotency table for swap execution results."

  @spec start_link(keyword()) :: Agent.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name, nil)

    case name do
      nil -> Agent.start_link(fn -> %{} end, opts)
      name -> Agent.start_link(fn -> %{} end, Keyword.put(opts, :name, name))
    end
  end

  @spec execute(pid() | atom(), String.t(), (-> term())) :: term()
  def execute(table, swap_ref, fun)
      when (is_pid(table) or is_atom(table)) and is_binary(swap_ref) and is_function(fun, 0) do
    Agent.get_and_update(table, fn state ->
      case Map.fetch(state, swap_ref) do
        {:ok, cached} ->
          {cached, state}

        :error ->
          result = fun.()
          {result, Map.put(state, swap_ref, result)}
      end
    end)
  end
end
