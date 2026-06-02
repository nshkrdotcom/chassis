defmodule Chassis.Doctor do
  @moduledoc """
  Diagnostics runner. Each check is a `{name, 0-arity-fun}` returning
  `:ok` / `{:error, term()}` / raising. `Doctor.run/1` walks the list,
  aggregates pass/fail, and returns either `{:ok, report}` (every check
  passed) or `{:error, report}` (one or more failed). Raised exceptions
  are rescued into `{:check_raised, msg}` so a bad check does not crash
  the diagnostic run.
  """

  @type check :: {atom(), (-> :ok | {:error, term()})}

  @default_checks [
    {:beam_alive, &__MODULE__.check_beam_alive/0},
    {:tmp_writable, &__MODULE__.check_tmp_writable/0}
  ]

  @spec run(keyword()) :: {:ok, map()} | {:error, map()}
  def run(opts \\ []) do
    checks = Keyword.get(opts, :checks, @default_checks)

    {passed, failed} =
      Enum.reduce(checks, {[], []}, fn {name, fun}, {pass, fail} ->
        case safe_call(fun) do
          :ok -> {pass ++ [name], fail}
          {:error, reason} -> {pass, fail ++ [{name, reason}]}
        end
      end)

    report = %{
      status: if(failed == [], do: :healthy, else: :unhealthy),
      checks_passed: passed,
      checks_failed: failed,
      ran_at: DateTime.utc_now()
    }

    if failed == [], do: {:ok, report}, else: {:error, report}
  end

  defp safe_call(fun) do
    fun.()
  rescue
    e -> {:error, {:check_raised, Exception.message(e)}}
  end

  @doc false
  def check_beam_alive do
    if is_pid(:erlang.whereis(:init)), do: :ok, else: {:error, :init_not_running}
  end

  @doc false
  def check_tmp_writable do
    tmp = System.tmp_dir!()
    probe = Path.join(tmp, "chassis_doctor_probe_" <> random_suffix())

    case File.write(probe, "ok") do
      :ok ->
        File.rm(probe)
        :ok

      {:error, reason} ->
        {:error, {:tmp_write_failed, reason}}
    end
  end

  defp random_suffix do
    Base.encode16(:crypto.strong_rand_bytes(4), case: :lower)
  end
end

defmodule Chassis.Doctor.NodeDiagnostics do
  @moduledoc "Local node BEAM diagnostics."
  @spec check(String.t()) :: {:ok, map()}
  def check(node_ref) do
    {:ok,
     %{
       node_ref: node_ref,
       beam_alive?: is_pid(:erlang.whereis(:init)),
       node_name: node(),
       schedulers: System.schedulers(),
       checked_at: DateTime.utc_now()
     }}
  end
end

defmodule Chassis.Doctor.HostDiagnostics do
  @moduledoc "Per-host diagnostics: returns the host record with checked_at stamped."
  @spec check(map()) :: {:ok, map()} | {:error, :missing_host_ref}
  def check(%{host_ref: ref} = host) when is_binary(ref) do
    {:ok, Map.put(host, :checked_at, DateTime.utc_now())}
  end

  def check(_), do: {:error, :missing_host_ref}
end

defmodule Chassis.Doctor.MeshDiagnostics do
  @moduledoc """
  Mesh diagnostics. A mesh with zero peers reports `:degraded`; one or more
  peers reports `:healthy`. Phase 9 (`chassis_mesh`) wires the real peer
  list; Phase 7 accepts the peer list as an option for testability.
  """
  @spec check(String.t(), keyword()) :: {:ok, map()}
  def check(mesh_ref, opts \\ []) do
    peers = Keyword.get(opts, :peers, [])
    status = if Enum.empty?(peers), do: :degraded, else: :healthy
    {:ok, %{mesh_ref: mesh_ref, peer_count: length(peers), status: status}}
  end
end
