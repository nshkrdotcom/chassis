defmodule Chassis.Provisioning.Adapter do
  @moduledoc """
  Provisioning adapter behaviour per
  `0507_provisioning_adapter_architecture.md` §1.
  """
  @callback prepare_host(map(), map(), map()) :: {:ok, map()} | {:error, term()}
end

defmodule Chassis.Provisioning.SSHBootstrap do
  @moduledoc """
  SSH-driven host bootstrap state machine per
  `0507_provisioning_adapter_architecture.md` §4.

  The state machine walks the documented step list:

      [:fence_acquire, :connect, :sftp_open, :ephemeral_dir,
       :upload_setup_script, :exec_setup_script, :install_unit,
       :start_unit, :verify_mesh_join]

  and halts at the first non-ok step. Every step is recorded into a
  `Chassis.Receipts.ProvisioningRecord` written to the configured
  `receipts_store:` GenServer.

  Transport is injected via `transport: {Module, ref}` so tests can
  substitute an in-memory recorder. The real transport (used in Phase 8 when
  `adapters/chassis_ssh` activates) is `Chassis.Adapters.SSH` and wraps
  Erlang's `:ssh`, `:ssh_connection`, and `:ssh_sftp` modules — never the
  external `ssh` / `sftp` / `scp` binaries.
  """
  @behaviour Chassis.Provisioning.Adapter

  alias Chassis.Receipts.{ProvisioningRecord, Store}

  @steps [
    :fence_acquire,
    :connect,
    :sftp_open,
    :ephemeral_dir,
    :upload_setup_script,
    :exec_setup_script,
    :install_unit,
    :start_unit,
    :verify_mesh_join
  ]

  @doc """
  Adapter contract entry. `opts` is a 3-argument call; the four-argument
  variant takes `transport:` / `receipts_store:` keyword options.
  """
  @impl true
  @spec prepare_host(map(), map(), map()) :: {:ok, map()} | {:error, term()}
  def prepare_host(host, config, lease), do: prepare_host(host, config, lease, [])

  @spec prepare_host(map(), map(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def prepare_host(host, config, lease, opts) do
    transport = Keyword.get(opts, :transport)
    store = Keyword.get(opts, :receipts_store)

    if is_nil(transport) do
      {:error, :missing_transport}
    else
      run(host, config, lease, transport, store)
    end
  end

  defp run(host, config, lease, transport, store) do
    state = %{
      host: host,
      config: config,
      lease: lease,
      transport: transport,
      completed_steps: [],
      conn: nil,
      sftp: nil,
      remote_dir: nil,
      started_at: System.monotonic_time(:millisecond)
    }

    case execute_pipeline(@steps, state) do
      {:ok, final_state} ->
        receipt = build_receipt(final_state, :ok, nil)
        maybe_store(store, receipt)
        {:ok, %{host_ref: host[:host_ref], lease_ref: lease[:lease_ref], steps: receipt.steps, status: :ok}}

      {:error, %{step: step, reason: reason} = err, partial_state} ->
        receipt = build_receipt(partial_state, :failed, reason)
        maybe_store(store, receipt)
        {:error, %{step: step, reason: reason, host_ref: host[:host_ref]} |> Map.merge(err)}
    end
  end

  defp execute_pipeline([], state), do: {:ok, state}

  defp execute_pipeline([step | rest], state) do
    case do_step(step, state) do
      {:ok, new_state} ->
        execute_pipeline(rest, %{new_state | completed_steps: [step | new_state.completed_steps]})

      {:error, reason} ->
        {:error, %{step: step, reason: reason}, %{state | completed_steps: [step | state.completed_steps]}}
    end
  end

  defp do_step(:fence_acquire, state) do
    # Phase 7 fence is a no-op placeholder; real fence lands with
    # GroundPlane.Contracts.Fence integration (Phase 12).
    {:ok, state}
  end

  defp do_step(:connect, %{transport: {mod, t}} = state) do
    case mod.connect(t, state.host, ssh_user: state.host[:ssh_user], ssh_port: state.host[:ssh_port]) do
      {:ok, conn} -> {:ok, %{state | conn: conn}}
      {:error, _} = err -> err
    end
  end

  defp do_step(:sftp_open, %{transport: {mod, t}, conn: conn} = state) do
    case mod.sftp_open(t, conn) do
      {:ok, sftp} -> {:ok, %{state | sftp: sftp}}
      {:error, _} = err -> err
    end
  end

  defp do_step(:ephemeral_dir, %{transport: {mod, t}, conn: conn} = state) do
    dir = "/tmp/chassis_bootstrap_" <> random_suffix()

    case mod.exec(t, conn, "mkdir -p #{dir} && chmod 0700 #{dir}") do
      {:ok, _} -> {:ok, %{state | remote_dir: dir}}
      {:error, _} = err -> err
    end
  end

  defp do_step(:upload_setup_script, %{transport: {mod, t}, sftp: sftp, remote_dir: dir, config: config} = state) do
    script = Enum.join(Map.get(config, :setup_script, []), "\n") <> "\n"
    remote_path = Path.join(dir, "setup.sh")

    case mod.upload(t, sftp, remote_path, script) do
      :ok -> {:ok, state}
      {:error, _} = err -> err
    end
  end

  defp do_step(:exec_setup_script, %{transport: {mod, t}, conn: conn, remote_dir: dir} = state) do
    case mod.exec(t, conn, "/bin/sh #{Path.join(dir, "setup.sh")}") do
      {:ok, %{exit_status: 0}} -> {:ok, state}
      {:ok, %{exit_status: code}} -> {:error, {:setup_script_nonzero_exit, code}}
      {:error, _} = err -> err
    end
  end

  defp do_step(:install_unit, %{transport: {mod, t}, conn: conn} = state) do
    case mod.exec(t, conn, "systemctl daemon-reload") do
      {:ok, _} -> {:ok, state}
      {:error, _} = err -> err
    end
  end

  defp do_step(:start_unit, %{transport: {mod, t}, conn: conn} = state) do
    case mod.exec(t, conn, "systemctl start chassis-host-daemon") do
      {:ok, _} -> {:ok, state}
      {:error, _} = err -> err
    end
  end

  defp do_step(:verify_mesh_join, %{transport: {mod, t}, conn: conn} = state) do
    case mod.exec(t, conn, "epmd -names") do
      {:ok, _} ->
        _ = mod.close(t, conn)
        {:ok, state}

      {:error, _} = err ->
        _ = mod.close(t, conn)
        err
    end
  end

  defp build_receipt(state, status, error) do
    duration = System.monotonic_time(:millisecond) - state.started_at

    %ProvisioningRecord{
      receipt_ref: Chassis.Receipts.new_ref("receipt:provisioning"),
      host_ref: state.host[:host_ref],
      attempt: 1,
      steps: Enum.reverse(state.completed_steps),
      status: status,
      error: error,
      duration_ms: max(duration, 0)
    }
  end

  defp maybe_store(nil, _record), do: :ok

  defp maybe_store(store, record) do
    case Store.Memory.put(store, record) do
      {:ok, _} -> :ok
      _ -> :ok
    end
  end

  defp random_suffix do
    Base.encode16(:crypto.strong_rand_bytes(4), case: :lower)
  end

  @doc """
  Create a host-local ephemeral directory with `0700` permissions. The
  cleanup-callback registration with `Chassis.Secrets.LeaseSupervisor`
  is wired in Phase 10 when the secrets plane activates.
  """
  @spec make_ephemeral_user_dir(String.t()) :: {:ok, String.t()}
  def make_ephemeral_user_dir(prefix) do
    path = Path.join(System.tmp_dir!(), prefix <> "_" <> random_suffix())
    File.mkdir_p!(path)
    File.chmod!(path, 0o700)
    {:ok, path}
  end

  @doc """
  Generate the systemd unit body for a chassis-installed service.

  Per `0507_provisioning_adapter_architecture.md` §4:
  * `EnvironmentFile=/opt/nshkr/secrets/service.env` (rendered from SOPS)
  * `Restart=on-failure`
  * `ExecStart` derived from the service `:command`.
  """
  @spec exec_unit_install(map(), map()) :: {:ok, String.t()}
  def exec_unit_install(service, _host) do
    exec = Map.get(service, :command, "/bin/true")

    {:ok,
     """
     [Service]
     EnvironmentFile=/opt/nshkr/secrets/service.env
     Restart=on-failure
     ExecStart=#{exec}
     """}
  end

  @doc """
  Verify a freshly-bootstrapped node joins the BEAM mesh. Real impl in
  Phase 9 (`chassis_mesh`) calls `:net_kernel.connect_node/1` +
  `:rpc.call/4`; Phase 7 returns a deterministic ok-shape so smoke tests
  exercise the state machine.
  """
  @spec verify_mesh_join(atom(), atom(), map()) :: {:ok, map()}
  def verify_mesh_join(node_name, _cookie, _opts), do: {:ok, %{node: node_name, connected?: true}}
end

defmodule Chassis.Provisioning.LocalNoop do
  @moduledoc "Local dev provisioning adapter — produces a :prepared receipt without any transport."
  @behaviour Chassis.Provisioning.Adapter

  @impl true
  @spec prepare_host(map(), map(), map()) :: {:ok, map()}
  def prepare_host(host, _config, _lease) do
    {:ok, %{host_ref: Map.get(host, :host_ref), status: :prepared}}
  end
end

defmodule Chassis.Provisioning.TofuProvisioner do
  @moduledoc """
  OpenTofu provisioning adapter. Phase 7 placeholder per 0541 §1 row 4 —
  real implementation lands when the workspace gains an OpenTofu binary
  shipment (not in the 0-43 phase plan).
  """
  @behaviour Chassis.Provisioning.Adapter

  @impl true
  @spec prepare_host(map(), map(), map()) :: {:error, {:not_implemented, module()}}
  def prepare_host(_host, _config, _lease), do: {:error, {:not_implemented, __MODULE__}}
end

defmodule Chassis.Provisioning.AnsibleAdapter do
  @moduledoc """
  Ansible provisioning adapter. Phase 7 placeholder per 0541 §1 row 4.
  """
  @behaviour Chassis.Provisioning.Adapter

  @impl true
  @spec prepare_host(map(), map(), map()) :: {:error, {:not_implemented, module()}}
  def prepare_host(_host, _config, _lease), do: {:error, {:not_implemented, __MODULE__}}
end

defmodule Chassis.Bootstrap do
  @moduledoc "Workspace bootstrap facade."
  @spec init(keyword()) :: {:ok, map()}
  def init(opts \\ []), do: {:ok, %{status: :initialized, opts: opts}}
end
