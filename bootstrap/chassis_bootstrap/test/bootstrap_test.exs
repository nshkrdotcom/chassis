defmodule Chassis.BootstrapTest do
  @moduledoc """
  Phase 7 — `chassis_bootstrap` SSH-driven host bootstrap state machine.

  The state machine is real: `prepare_host/3` walks
  `[:fence_acquire, :connect, :sftp_open, :ephemeral_dir, :upload_setup_script,
   :exec_setup_script, :install_unit, :start_unit, :verify_mesh_join]`
  in order and stops at the first non-`:ok` step. The transport is injected
  (`transport:` option) and tests use an in-memory `FakeSSHTransport` to
  record every call. A `ProvisioningRecord` is written to the configured
  receipts store at the end.

  The OpenTofu and Ansible adapters MUST return
  `{:error, {:not_implemented, __MODULE__}}` per 0541 §1 row 4.
  """
  use ExUnit.Case, async: false

  alias Chassis.Provisioning.{Adapter, AnsibleAdapter, LocalNoop, SSHBootstrap, TofuProvisioner}
  alias Chassis.Receipts.{ProvisioningRecord, Store}

  defmodule FakeSSHTransport do
    @moduledoc "Records every call so tests can verify the bootstrap state machine."
    use Agent

    def start_link(opts \\ []) do
      Agent.start_link(fn -> %{calls: [], opts: opts, fail_step: Keyword.get(opts, :fail_step)} end)
    end

    def calls(t), do: Agent.get(t, & &1.calls) |> Enum.reverse()

    defp record(t, call) do
      Agent.update(t, fn st -> %{st | calls: [call | st.calls]} end)
      :ok
    end

    defp maybe_fail(t, step, ok_value) do
      fs = Agent.get(t, & &1.fail_step)
      if fs == step, do: {:error, {:transport_failed, step}}, else: ok_value
    end

    def connect(t, host, opts) do
      record(t, {:connect, host, opts})
      maybe_fail(t, :connect, {:ok, {:conn, host.host_ref}})
    end

    def sftp_open(t, conn) do
      record(t, {:sftp_open, conn})
      maybe_fail(t, :sftp_open, {:ok, {:sftp, conn}})
    end

    def upload(t, sftp, remote_path, body) do
      record(t, {:upload, sftp, remote_path, byte_size(body)})
      maybe_fail(t, :upload_setup_script, :ok)
    end

    def exec(t, conn, cmd) do
      record(t, {:exec, conn, cmd})

      step =
        cond do
          cmd =~ "mkdir -p" -> :ephemeral_dir
          cmd =~ "/bin/sh" -> :exec_setup_script
          cmd =~ "systemctl daemon-reload" -> :install_unit
          cmd =~ "systemctl start" -> :start_unit
          cmd =~ "epmd" -> :verify_mesh_join
          true -> :exec
        end

      maybe_fail(t, step, {:ok, %{stdout: "", stderr: "", exit_status: 0}})
    end

    def close(t, conn) do
      record(t, {:close, conn})
      :ok
    end
  end

  setup do
    {:ok, store} = Store.Memory.start_link(name: nil)
    {:ok, transport} = FakeSSHTransport.start_link()

    host = %{
      host_ref: "host:fake-1",
      hostname: "10.0.0.1",
      ip_address: "10.0.0.1",
      ssh_port: 22,
      ssh_user: "root"
    }

    env = %{
      env_config_ref: "linode_ubuntu_24_04",
      setup_script: ["apt-get update", "install erlang elixir"],
      install_paths: %{release: "/opt/nshkr/releases"}
    }

    lease = %{lease_ref: "lease:fake:abc", secret_ref: "secret:ssh_key:bootstrap", material: "FAKE-KEY-BYTES"}

    %{store: store, transport: transport, host: host, env: env, lease: lease}
  end

  describe "Adapter behaviour contract" do
    test "Adapter declares prepare_host/3 callback" do
      assert {:prepare_host, 3} in Adapter.behaviour_info(:callbacks)
    end

    test "SSHBootstrap, LocalNoop, TofuProvisioner, AnsibleAdapter all declare @behaviour" do
      for mod <- [SSHBootstrap, LocalNoop, TofuProvisioner, AnsibleAdapter] do
        attrs = mod.module_info(:attributes)
        assert Adapter in (attrs[:behaviour] || []), "#{inspect(mod)} missing @behaviour"
      end
    end
  end

  describe "SSHBootstrap.prepare_host/3 — full happy-path state machine" do
    test "executes every documented step in order and returns a successful ProvisioningRecord", %{store: store, transport: t, host: host, env: env, lease: lease} do
      assert {:ok, receipt} =
               SSHBootstrap.prepare_host(host, env, lease,
                 transport: {FakeSSHTransport, t},
                 receipts_store: store
               )

      assert receipt.host_ref == "host:fake-1"
      assert receipt.status == :ok
      assert receipt.steps == [
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

      # The transport was actually called
      calls = FakeSSHTransport.calls(t)
      assert Enum.any?(calls, &match?({:connect, _, _}, &1))
      assert Enum.any?(calls, &match?({:sftp_open, _}, &1))
      assert Enum.any?(calls, &match?({:upload, _, _, _}, &1))
      assert Enum.any?(calls, &match?({:exec, _, _}, &1))
      assert Enum.any?(calls, &match?({:close, _}, &1))
    end

    test "writes a ProvisioningRecord to the receipts store", %{store: store, transport: t, host: host, env: env, lease: lease} do
      {:ok, _receipt} =
        SSHBootstrap.prepare_host(host, env, lease,
          transport: {FakeSSHTransport, t},
          receipts_store: store
        )

      records = Store.Memory.list(store, kind: ProvisioningRecord)
      assert [record] = records
      assert record.host_ref == "host:fake-1"
      assert record.status == :ok
      assert :verify_mesh_join in record.steps
    end
  end

  describe "SSHBootstrap.prepare_host/3 — unhappy paths halt the state machine" do
    test "fails fast when the SSH connect step fails", %{store: store, host: host, env: env, lease: lease} do
      {:ok, t} = FakeSSHTransport.start_link(fail_step: :connect)

      assert {:error, %{step: :connect, reason: {:transport_failed, :connect}}} =
               SSHBootstrap.prepare_host(host, env, lease,
                 transport: {FakeSSHTransport, t},
                 receipts_store: store
               )

      assert [record] = Store.Memory.list(store, kind: ProvisioningRecord)
      assert record.status == :failed
      assert record.error == {:transport_failed, :connect}
      # No steps past :connect should be in the receipt
      refute :exec_setup_script in record.steps
    end

    test "fails fast when upload step fails", %{store: store, host: host, env: env, lease: lease} do
      {:ok, t} = FakeSSHTransport.start_link(fail_step: :upload_setup_script)

      assert {:error, %{step: :upload_setup_script}} =
               SSHBootstrap.prepare_host(host, env, lease,
                 transport: {FakeSSHTransport, t},
                 receipts_store: store
               )

      [record] = Store.Memory.list(store, kind: ProvisioningRecord)
      assert record.status == :failed
      refute :exec_setup_script in record.steps
    end

    test "fails fast when verify_mesh_join step fails", %{store: store, host: host, env: env, lease: lease} do
      {:ok, t} = FakeSSHTransport.start_link(fail_step: :verify_mesh_join)

      assert {:error, %{step: :verify_mesh_join}} =
               SSHBootstrap.prepare_host(host, env, lease,
                 transport: {FakeSSHTransport, t},
                 receipts_store: store
               )

      [record] = Store.Memory.list(store, kind: ProvisioningRecord)
      assert record.status == :failed
      assert :start_unit in record.steps
    end

    test "transport must be supplied — omitting it returns a structured error", %{host: host, env: env, lease: lease, store: store} do
      assert {:error, :missing_transport} =
               SSHBootstrap.prepare_host(host, env, lease, receipts_store: store)
    end
  end

  describe "SSHBootstrap helper functions" do
    test "make_ephemeral_user_dir/1 creates a 0700 directory with random suffix" do
      {:ok, path} = SSHBootstrap.make_ephemeral_user_dir("test_prefix")
      assert File.exists?(path)
      assert File.stat!(path).mode |> Bitwise.band(0o777) == 0o700
      assert Path.basename(path) =~ ~r/^test_prefix_/
      File.rm_rf!(path)
    end

    test "exec_unit_install/2 generates a systemd unit with EnvironmentFile and Restart" do
      service = %{
        service_ref: "service:demo",
        command: "/opt/nshkr/releases/demo/bin/demo start"
      }

      {:ok, unit} = SSHBootstrap.exec_unit_install(service, %{host_ref: "host:1"})
      assert unit =~ "EnvironmentFile=/opt/nshkr/secrets/service.env"
      assert unit =~ "Restart=on-failure"
      assert unit =~ "ExecStart=/opt/nshkr/releases/demo/bin/demo start"
    end
  end

  describe "LocalNoop adapter" do
    test "returns an ok receipt for any host with status :prepared", %{host: host, env: env, lease: lease} do
      assert {:ok, %{host_ref: "host:fake-1", status: :prepared}} =
               LocalNoop.prepare_host(host, env, lease)
    end
  end

  describe "TofuProvisioner and AnsibleAdapter are explicit not_implemented" do
    test "TofuProvisioner returns canonical not_implemented", %{host: host, env: env, lease: lease} do
      assert {:error, {:not_implemented, TofuProvisioner}} =
               TofuProvisioner.prepare_host(host, env, lease)
    end

    test "AnsibleAdapter returns canonical not_implemented", %{host: host, env: env, lease: lease} do
      assert {:error, {:not_implemented, AnsibleAdapter}} =
               AnsibleAdapter.prepare_host(host, env, lease)
    end
  end

  describe "spine audit: no shell-out to external ssh binary" do
    test "SSHBootstrap module does not call System.cmd('ssh', _)" do
      source = File.read!(Path.join(File.cwd!(), "lib/chassis/bootstrap.ex"))
      refute source =~ ~r/System\.cmd\(\s*"ssh"/
      refute source =~ ~r/System\.cmd\(\s*"sftp"/
      refute source =~ ~r/System\.cmd\(\s*"scp"/
    end
  end
end
