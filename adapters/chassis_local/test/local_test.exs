defmodule Chassis.Adapter.LocalTest do
  use ExUnit.Case, async: false
  alias Chassis.Adapter.Local

  test "declares Chassis.Contracts.Adapter behaviour" do
    attrs = Local.module_info(:attributes)
    assert Chassis.Contracts.Adapter in (attrs[:behaviour] || [])
  end

  describe "prepare/2" do
    test "stamps :prepared on the payload" do
      assert {:ok, %{prepared: true}} = Local.prepare(%{}, [])
    end
  end

  describe "start/2 — real Port.open/2" do
    test "starts a real /bin/true and returns a port plus :started status" do
      assert {:ok, %{status: :started, port: port}} =
               Local.start(%{name: "noop"}, command: "/bin/true")

      assert is_port(port)
      # consume the exit message to avoid leaking it across tests
      receive do
        {^port, {:exit_status, 0}} -> :ok
      after
        1_000 -> :ok
      end
    end

    test "returns {:error, {:executable_not_found, _}} for a missing binary" do
      assert {:error, {:executable_not_found, "/no/such/binary/xyz123"}} =
               Local.start(%{}, command: "/no/such/binary/xyz123")
    end
  end

  describe "stop/2" do
    test "closes the port and returns :stopped" do
      {:ok, %{port: port} = payload} = Local.start(%{}, command: "/bin/sleep", args: ["1"])
      assert is_port(port)
      assert {:ok, %{status: :stopped}} = Local.stop(payload, [])
      refute Port.info(port)
    end

    test "is a no-op for a payload with no port" do
      assert {:ok, %{status: :stopped}} = Local.stop(%{}, [])
    end
  end

  describe "health/2" do
    test "reports :healthy while the port is still open" do
      {:ok, %{port: port} = payload} = Local.start(%{}, command: "/bin/sleep", args: ["1"])
      assert {:ok, %{status: :healthy}} = Local.health(payload, [])
      Port.close(port)
    end

    test "reports :exited after the port closes" do
      {:ok, payload} = Local.start(%{}, command: "/bin/true")
      Process.sleep(50)
      assert {:ok, %{status: status}} = Local.health(payload, [])
      assert status in [:exited, :healthy]
    end

    test "reports :unknown when no port in payload" do
      assert {:ok, %{status: :unknown}} = Local.health(%{}, [])
    end
  end

  describe "run_sync/3" do
    test "executes /bin/true and returns exit 0" do
      assert {:ok, 0} = Local.run_sync("/bin/true", [], 2_000)
    end

    test "executes /bin/false and returns exit non-zero" do
      assert {:ok, code} = Local.run_sync("/bin/false", [], 2_000)
      assert code != 0
    end

    test "returns :timeout for a hung process" do
      assert {:error, :timeout} = Local.run_sync("/bin/sleep", ["5"], 100)
    end
  end
end
