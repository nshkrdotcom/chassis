defmodule Chassis.Adapter.SystemdTest do
  use ExUnit.Case, async: true
  alias Chassis.Adapter.Systemd

  defmodule FakeCmd do
    def cmd(_bin, _args, _opts), do: {Application.get_env(:test, :fake_cmd, "active\n"), 0}
  end

  test "declares @behaviour Chassis.Contracts.Adapter" do
    attrs = Systemd.module_info(:attributes)
    assert Chassis.Contracts.Adapter in (attrs[:behaviour] || [])
  end

  describe "unit_file/1" do
    test "renders [Unit] [Service] [Install] sections with EnvironmentFile and Restart" do
      out =
        Systemd.unit_file(%{
          name: "demo",
          command: "/opt/nshkr/releases/demo/bin/demo start",
          user: "nshkr"
        })

      assert out =~ "[Unit]"
      assert out =~ "[Service]"
      assert out =~ "[Install]"
      assert out =~ "Description=demo"
      assert out =~ "EnvironmentFile=/opt/nshkr/secrets/service.env"
      assert out =~ "Restart=on-failure"
      assert out =~ "ExecStart=/opt/nshkr/releases/demo/bin/demo start"
      assert out =~ "User=nshkr"
      assert out =~ "WantedBy=multi-user.target"
    end

    test "honors a custom env_file override" do
      out = Systemd.unit_file(%{env_file: "/tmp/custom.env"})
      assert out =~ "EnvironmentFile=/tmp/custom.env"
    end
  end

  describe "systemctl/3 with injected cmd module" do
    test "returns {:ok, %{stdout, exit_status}}" do
      assert {:ok, %{stdout: "active\n", exit_status: 0}} =
               Systemd.systemctl("is-active", ["nginx"], cmd_module: FakeCmd)
    end

    test "returns {:error, :systemctl_not_found} when binary is missing" do
      assert {:error, :systemctl_not_found} =
               Systemd.systemctl("is-active", [], bin: "/no/such/binary/xyz")
    end
  end

  describe "prepare/2 / start/2 / stop/2 / health/2" do
    test "prepare stamps :unit_file" do
      {:ok, out} = Systemd.prepare(%{name: "x", command: "/bin/true"}, [])
      assert out.unit_file =~ "[Service]"
    end

    test "start without unit_name returns :missing_unit_name" do
      assert {:error, :missing_unit_name} = Systemd.start(%{}, [])
    end

    test "stop without unit_name returns :missing_unit_name" do
      assert {:error, :missing_unit_name} = Systemd.stop(%{}, [])
    end

    test "health with injected cmd returns parsed :active" do
      assert {:ok, %{status: :active}} = Systemd.health(%{unit_name: "x"}, cmd_module: FakeCmd)
    end
  end
end
