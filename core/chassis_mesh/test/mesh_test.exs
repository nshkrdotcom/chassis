defmodule Chassis.MeshTest do
  @moduledoc """
  Phase 9 — `chassis_mesh` BEAM TLS distribution + health + :pg group tests.

  Tests live cert generation via `:public_key` + `:crypto` (per-cluster CA
  + per-node cert), an `Adapter` behaviour, the `LocalLoopback` and
  `BEAMDistribution` adapters, the `HealthSupervisor` periodic loop, and
  `:pg` group sync per virtual server.
  """
  use ExUnit.Case, async: false

  alias Chassis.Mesh.{Adapter, BEAMDistribution, HealthSupervisor, LocalLoopback, TlsKit}

  describe "Adapter behaviour contract" do
    test "declares the three documented callbacks" do
      cbs = Adapter.behaviour_info(:callbacks) |> MapSet.new()

      assert MapSet.subset?(
               MapSet.new([{:init_node, 1}, {:join_group, 2}, {:health, 1}]),
               cbs
             )
    end

    test "BEAMDistribution and LocalLoopback both declare @behaviour" do
      for mod <- [BEAMDistribution, LocalLoopback] do
        attrs = mod.module_info(:attributes)
        assert Adapter in (attrs[:behaviour] || []), "#{inspect(mod)} missing @behaviour"
      end
    end
  end

  describe "TlsKit.generate_cluster_material/1 produces real X.509 PEMs" do
    test "returns ca_pem, ca_key_pem, and a stable cluster_ref" do
      mat = TlsKit.generate_cluster_material("cluster:test")
      assert mat.cluster_ref == "cluster:test"
      assert is_binary(mat.ca_pem)
      assert mat.ca_pem =~ "-----BEGIN CERTIFICATE-----"
      assert mat.ca_pem =~ "-----END CERTIFICATE-----"
      assert is_binary(mat.ca_key_pem)
      assert mat.ca_key_pem =~ "-----BEGIN RSA PRIVATE KEY-----"
    end

    test "the CA PEM is a parseable X.509 certificate" do
      mat = TlsKit.generate_cluster_material("cluster:parse")
      [{:Certificate, der, :not_encrypted}] = :public_key.pem_decode(mat.ca_pem)
      assert is_binary(der) and byte_size(der) > 0
    end
  end

  describe "TlsKit.generate_node_cert/2 signs node certs against the cluster CA" do
    setup do
      %{cluster: TlsKit.generate_cluster_material("cluster:nodes")}
    end

    test "issues a node cert + key", %{cluster: cluster} do
      node = TlsKit.generate_node_cert(cluster, "node-1@127.0.0.1")
      assert node.node_name == "node-1@127.0.0.1"
      assert node.cert_pem =~ "-----BEGIN CERTIFICATE-----"
      assert node.key_pem =~ "-----BEGIN RSA PRIVATE KEY-----"
    end

    test "distinct nodes produce distinct certs", %{cluster: cluster} do
      a = TlsKit.generate_node_cert(cluster, "a@127.0.0.1")
      b = TlsKit.generate_node_cert(cluster, "b@127.0.0.1")
      assert a.cert_pem != b.cert_pem
    end
  end

  describe "TlsKit redaction" do
    test "Inspect of cluster material masks ca_key_pem" do
      mat = TlsKit.generate_cluster_material("cluster:secret")
      inspected = inspect(mat)
      refute inspected =~ mat.ca_key_pem
    end
  end

  describe "BEAMDistribution.init_node/1" do
    test "returns mesh_status: :joined with configurable dist port range" do
      assert {:ok, result} =
               BEAMDistribution.init_node(%{node: :"x@127.0.0.1", inet_dist_listen_min: 10_000, inet_dist_listen_max: 10_100})

      assert result.mesh_status == :joined
      assert result.dist_ports == 10_000..10_100
    end

    test "default port range is configurable to the documented 9100..9200" do
      {:ok, result} = BEAMDistribution.init_node(%{node: :"x@127.0.0.1"})
      assert result.dist_ports == 9100..9200
    end

    test "rejects a config with no node" do
      assert {:error, :missing_node} = BEAMDistribution.init_node(%{})
    end
  end

  describe "LocalLoopback delegates and reports a single-node mesh" do
    test "init_node returns mesh_status :joined" do
      assert {:ok, %{mesh_status: :joined}} = LocalLoopback.init_node(%{node: node()})
    end

    test "health reports the local node" do
      assert {:ok, %{status: :healthy, node: n}} = LocalLoopback.health(%{node: node()})
      assert n == node()
    end
  end

  describe ":pg group sync per virtual server" do
    setup do
      _ = :pg.start_link(:chassis_mesh)
      :ok
    end

    test "join_group registers the calling pid in the named group" do
      group = {:vs_app_kit, :test}
      assert :ok = BEAMDistribution.join_group(group, self())
      assert self() in :pg.get_members(:chassis_mesh, group)
    end

    test "two pids in the same group are both reported" do
      group = {:vs_mezzanine, :test}
      pid = spawn(fn -> Process.sleep(2_000) end)
      :ok = BEAMDistribution.join_group(group, self())
      :ok = BEAMDistribution.join_group(group, pid)
      members = :pg.get_members(:chassis_mesh, group)
      assert self() in members
      assert pid in members
      Process.exit(pid, :kill)
    end
  end

  describe "HealthSupervisor periodic loop" do
    test "check_once returns a structured report" do
      assert {:ok, report} = HealthSupervisor.check_once(%{cluster_ref: "cluster:x"})
      assert report.status == :healthy
      assert %DateTime{} = report.checked_at
      assert report.config.cluster_ref == "cluster:x"
    end

    test "start_link/1 runs at most N ticks then stops, recording each tick" do
      {:ok, sup} = HealthSupervisor.start_link(interval_ms: 50, max_ticks: 3, name: nil)
      Process.sleep(200)
      ticks = HealthSupervisor.ticks(sup)
      assert length(ticks) >= 3
      Process.exit(sup, :kill)
    end
  end

  describe "spine audit" do
    test "TlsKit module uses :public_key + :crypto, not external openssl shell-out" do
      source = File.read!(Path.join(File.cwd!(), "lib/chassis/mesh.ex"))
      refute source =~ ~r/System\.cmd\(\s*"openssl"/
      assert source =~ ":public_key"
      assert source =~ ":crypto"
    end
  end
end
