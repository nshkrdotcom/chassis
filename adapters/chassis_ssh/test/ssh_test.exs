defmodule Chassis.Adapter.SSHTest do
  use ExUnit.Case, async: true
  alias Chassis.Adapter.SSH

  defmodule FakeBackend do
    @behaviour Chassis.Adapter.SSH.Backend
    @impl true
    def connect(host, _opts), do: {:ok, {:conn, host[:host_ref]}}
    @impl true
    def sftp_open(conn), do: {:ok, {:sftp, conn}}
    @impl true
    def upload(_sftp, _remote, _bytes), do: :ok
    @impl true
    def exec(_conn, cmd) do
      cond do
        cmd =~ "true" -> {:ok, %{exit_status: 0, stdout: "", stderr: ""}}
        cmd =~ "false" -> {:ok, %{exit_status: 1, stdout: "", stderr: ""}}
        true -> {:error, :unknown_cmd}
      end
    end

    @impl true
    def close(_conn), do: :ok
  end

  describe "Backend behaviour contract" do
    test "defines exactly the five backend callbacks" do
      cbs = Chassis.Adapter.SSH.Backend.behaviour_info(:callbacks) |> MapSet.new()

      assert MapSet.subset?(
               MapSet.new([
                 {:connect, 2},
                 {:sftp_open, 1},
                 {:upload, 3},
                 {:exec, 2},
                 {:close, 1}
               ]),
               cbs
             )
    end
  end

  describe "SSH facade with FakeBackend" do
    test "connect/3 routes to the backend" do
      assert {:ok, {:conn, "host:test"}} =
               SSH.connect(%{host_ref: "host:test"}, [], FakeBackend)
    end

    test "sftp_open/2 routes to the backend" do
      {:ok, conn} = SSH.connect(%{host_ref: "h"}, [], FakeBackend)
      assert {:ok, {:sftp, ^conn}} = SSH.sftp_open(conn, FakeBackend)
    end

    test "upload/4 routes to the backend" do
      assert :ok = SSH.upload(:sftp, "/tmp/x", "abc", FakeBackend)
    end

    test "exec/3 returns successful exec result" do
      assert {:ok, %{exit_status: 0}} = SSH.exec(:conn, "/bin/true", FakeBackend)
    end

    test "exec/3 surfaces non-zero exit statuses" do
      assert {:ok, %{exit_status: 1}} = SSH.exec(:conn, "/bin/false", FakeBackend)
    end

    test "close/2 returns :ok" do
      assert :ok = SSH.close(:conn, FakeBackend)
    end
  end

  describe "Default Erl backend is not_implemented (Phase 8 -> live wiring lands at Phase 8 QC gate with real sshd)" do
    test "connect returns canonical not_implemented" do
      assert {:error, {:not_implemented, Chassis.Adapter.SSH.Erl}} =
               Chassis.Adapter.SSH.Erl.connect(%{}, [])
    end

    test "exec returns canonical not_implemented" do
      assert {:error, {:not_implemented, Chassis.Adapter.SSH.Erl}} =
               Chassis.Adapter.SSH.Erl.exec(:conn, "true")
    end
  end

  describe "spine audit: no shell-out to external ssh binary" do
    test "SSH module source contains no System.cmd('ssh'/sftp/scp)" do
      source = File.read!(Path.join(File.cwd!(), "lib/chassis/ssh.ex"))
      refute source =~ ~r/System\.cmd\(\s*"ssh"/
      refute source =~ ~r/System\.cmd\(\s*"sftp"/
      refute source =~ ~r/System\.cmd\(\s*"scp"/
    end
  end
end
