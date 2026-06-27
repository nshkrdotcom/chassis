defmodule Chassis.InventoryTest do
  @moduledoc """
  Phase 3 — `chassis_inventory` behavioral tests.

  Covers the typed records (PhysicalHost, CapacityMap, GpuInventory), the
  placement validator, the static discovery (reading a JSON file at a
  configurable path), and the dynamic-discovery contracts — which today
  must return `{:error, {:not_implemented, __MODULE__}}` per 0541 §1 row 4
  until Phase 8 lands real HTTP clients.
  """
  use ExUnit.Case, async: true

  alias Chassis.Inventory.{
    CapacityMap,
    Discovery,
    DynamicDiscovery,
    GpuInventory,
    PhysicalHost,
    PlacementValidator,
    StaticDiscovery
  }

  describe "structs" do
    test "PhysicalHost defaults" do
      h = %PhysicalHost{host_ref: "host:x"}
      assert h.tenant_refs == []
      assert h.resources == %{}
    end

    test "CapacityMap defaults" do
      c = %CapacityMap{host_ref: "host:x"}
      assert c.total == %{}
      assert c.allocated == %{}
    end

    test "GpuInventory zero defaults" do
      g = %GpuInventory{host_ref: "host:x"}
      assert g.vram_gb == 0
      assert g.free_count == 0
    end
  end

  describe "PlacementValidator.check/2" do
    setup do
      %{
        gpu_host: %{
          host_ref: "host:gpu",
          resources: %{cpu_cores: 16, ram_gb: 64, gpus: 2, disk_gb: 1024}
        },
        cpu_host: %{
          host_ref: "host:cpu",
          resources: %{cpu_cores: 8, ram_gb: 32, gpus: 0, disk_gb: 256}
        }
      }
    end

    test "admits a placement that fits", %{cpu_host: h} do
      assert :ok = PlacementValidator.check(h, %{cpu_cores: 2, ram_gb: 4, gpus: 0})
    end

    test "rejects a GPU placement on a non-GPU host", %{cpu_host: h} do
      assert {:error, :gpu_unavailable} =
               PlacementValidator.check(h, %{cpu_cores: 1, ram_gb: 1, gpus: 1})
    end

    test "rejects an over-allocated CPU request", %{cpu_host: h} do
      assert {:error, :cpu_unavailable} =
               PlacementValidator.check(h, %{cpu_cores: 100, ram_gb: 1, gpus: 0})
    end

    test "rejects an over-allocated memory request", %{cpu_host: h} do
      assert {:error, :memory_unavailable} =
               PlacementValidator.check(h, %{cpu_cores: 1, ram_gb: 1024, gpus: 0})
    end

    test "rejects an over-allocated disk request when disk_gb is supplied", %{cpu_host: h} do
      assert {:error, :disk_unavailable} =
               PlacementValidator.check(h, %{cpu_cores: 1, ram_gb: 1, gpus: 0, disk_gb: 9999})
    end

    test "property: 100 random hosts × 100 random requests never admit constraint violations" do
      :rand.seed(:exsss, {1, 2, 3})

      for _i <- 1..100 do
        host = %{
          host_ref: "host:#{:rand.uniform(1_000_000)}",
          resources: %{
            cpu_cores: :rand.uniform(64),
            ram_gb: :rand.uniform(256),
            gpus: :rand.uniform(4) - 1,
            disk_gb: :rand.uniform(2048)
          }
        }

        request = %{
          cpu_cores: :rand.uniform(64),
          ram_gb: :rand.uniform(256),
          gpus: :rand.uniform(4) - 1,
          disk_gb: :rand.uniform(2048)
        }

        result = PlacementValidator.check(host, request)
        r = host.resources

        case result do
          :ok ->
            assert request.cpu_cores <= r.cpu_cores
            assert request.ram_gb <= r.ram_gb
            assert request.gpus <= r.gpus
            assert request.disk_gb <= r.disk_gb

          {:error, kind} ->
            assert kind in [
                     :cpu_unavailable,
                     :memory_unavailable,
                     :gpu_unavailable,
                     :disk_unavailable
                   ]
        end
      end
    end
  end

  describe "Discovery behaviour contract" do
    test "Discovery defines exactly one callback discover_hosts/1" do
      callbacks = Discovery.behaviour_info(:callbacks)
      assert {:discover_hosts, 1} in callbacks
    end
  end

  describe "StaticDiscovery reads from a JSON path" do
    setup do
      path =
        Path.join(System.tmp_dir!(), "chassis_hosts_#{System.unique_integer([:positive])}.json")

      File.write!(
        path,
        Jason.encode!([
          %{
            "host_ref" => "host:disk1",
            "provider" => "local",
            "region" => "local",
            "resources" => %{"cpu_cores" => 4, "ram_gb" => 8, "gpus" => 0},
            "tenant_refs" => ["tenant:dev"]
          },
          %{
            "host_ref" => "host:gpu1",
            "provider" => "fixture",
            "region" => "us-west",
            "resources" => %{"cpu_cores" => 16, "ram_gb" => 64, "gpus" => 1},
            "tenant_refs" => ["tenant:acme"]
          }
        ])
      )

      on_exit(fn -> File.rm(path) end)
      %{path: path}
    end

    test "discover_hosts(path: ...) returns the hosts from the file", %{path: path} do
      assert {:ok, hosts} = StaticDiscovery.discover_hosts(path: path)
      assert length(hosts) == 2
      assert Enum.find(hosts, &(&1.host_ref == "host:disk1"))
      assert Enum.find(hosts, &(&1.host_ref == "host:gpu1"))
    end

    test "tenant_ref filter returns only matching hosts", %{path: path} do
      assert {:ok, hosts} = StaticDiscovery.discover_hosts(path: path, tenant_ref: "tenant:acme")
      assert [%{host_ref: "host:gpu1"}] = hosts
    end

    test "top-level tenant_ref filters runbook-style host inventory files" do
      path =
        Path.join(
          System.tmp_dir!(),
          "chassis_hosts_wrapped_#{System.unique_integer([:positive])}.json"
        )

      File.write!(
        path,
        Jason.encode!(%{
          "version" => 1,
          "tenant_ref" => "tenant:wrapped",
          "hosts" => [
            %{
              "host_ref" => "host:wrapped",
              "provider" => "static",
              "region" => "local",
              "resources" => %{"cpu_cores" => 4, "ram_gb" => 8, "gpus" => 0},
              "tenant_refs" => ["tenant:wrapped"]
            },
            %{
              "host_ref" => "host:other",
              "provider" => "static",
              "region" => "local",
              "resources" => %{"cpu_cores" => 4, "ram_gb" => 8, "gpus" => 0},
              "tenant_refs" => ["tenant:other"]
            }
          ]
        })
      )

      on_exit(fn -> File.rm(path) end)

      assert {:ok, [%{host_ref: "host:wrapped"}]} = StaticDiscovery.discover_hosts(path: path)
    end

    test "normalization does not create atoms from unbounded JSON provider or resource keys" do
      provider = "provider_#{System.unique_integer([:positive])}"
      resource = "custom_resource_#{System.unique_integer([:positive])}"

      path =
        Path.join(
          System.tmp_dir!(),
          "chassis_hosts_safe_#{System.unique_integer([:positive])}.json"
        )

      File.write!(
        path,
        Jason.encode!([
          %{
            "host_ref" => "host:safe",
            "provider" => provider,
            "region" => "local",
            "resources" => %{
              "cpu_cores" => 4,
              "ram_gb" => 8,
              "gpus" => 0,
              resource => 1
            },
            "tenant_refs" => ["tenant:dev"]
          }
        ])
      )

      on_exit(fn -> File.rm(path) end)

      assert {:ok, [%{provider: ^provider, resources: resources}]} =
               StaticDiscovery.discover_hosts(path: path)

      assert resources.cpu_cores == 4
      assert Map.fetch!(resources, resource) == 1

      refute Enum.any?(Map.keys(resources), fn
               key when is_atom(key) -> Atom.to_string(key) == resource
               _key -> false
             end)
    end

    test "host_ref is the canonical join key (no IP-based join)", %{path: path} do
      {:ok, hosts} = StaticDiscovery.discover_hosts(path: path)

      for host <- hosts do
        assert is_binary(host.host_ref)
        assert String.starts_with?(host.host_ref, "host:")
      end
    end

    test "missing file returns {:error, :enoent}" do
      assert {:error, :enoent} = StaticDiscovery.discover_hosts(path: "/no/such/file.json")
    end

    test "malformed JSON returns {:error, {:json_decode, _}}" do
      bad = Path.join(System.tmp_dir!(), "bad_#{System.unique_integer([:positive])}.json")
      File.write!(bad, "{not-json")
      on_exit(fn -> File.rm(bad) end)
      assert {:error, {:json_decode, _}} = StaticDiscovery.discover_hosts(path: bad)
    end
  end

  describe "DynamicDiscovery providers are not-implemented placeholders (Phase 8 lands real HTTP)" do
    test "DynamicDiscovery.Linode.discover_hosts/1 returns canonical not_implemented" do
      assert {:error, {:not_implemented, DynamicDiscovery.Linode}} =
               DynamicDiscovery.Linode.discover_hosts([])
    end

    test "DynamicDiscovery.DigitalOcean returns canonical not_implemented" do
      assert {:error, {:not_implemented, DynamicDiscovery.DigitalOcean}} =
               DynamicDiscovery.DigitalOcean.discover_hosts([])
    end

    test "DynamicDiscovery.Hetzner returns canonical not_implemented" do
      assert {:error, {:not_implemented, DynamicDiscovery.Hetzner}} =
               DynamicDiscovery.Hetzner.discover_hosts([])
    end

    test "DynamicDiscovery.RunPod returns canonical not_implemented" do
      assert {:error, {:not_implemented, DynamicDiscovery.RunPod}} =
               DynamicDiscovery.RunPod.discover_hosts([])
    end

    test "DynamicDiscovery.VastAi returns canonical not_implemented" do
      assert {:error, {:not_implemented, DynamicDiscovery.VastAi}} =
               DynamicDiscovery.VastAi.discover_hosts([])
    end

    test "DynamicDiscovery facade routes via the configured provider (default: not_implemented)" do
      assert {:error, {:not_implemented, _}} = DynamicDiscovery.discover_hosts(provider: :linode)
      assert {:error, {:not_implemented, _}} = DynamicDiscovery.discover_hosts(provider: :hetzner)
    end

    test "DynamicDiscovery.discover_hosts/1 with no provider returns explicit error" do
      assert {:error, :missing_provider} = DynamicDiscovery.discover_hosts([])
    end
  end

  describe "CapacityMap tracking" do
    test "available/1 computes total - allocated for each resource key" do
      cap = %CapacityMap{
        host_ref: "host:x",
        total: %{cpu_cores: 16, ram_gb: 64, gpus: 2},
        allocated: %{cpu_cores: 4, ram_gb: 8, gpus: 1}
      }

      assert Chassis.Inventory.CapacityMap.available(cap) == %{cpu_cores: 12, ram_gb: 56, gpus: 1}
    end

    test "allocate/2 increments allocated counts and refuses over-commit" do
      cap = %CapacityMap{
        host_ref: "host:x",
        total: %{cpu_cores: 4, ram_gb: 8},
        allocated: %{cpu_cores: 0, ram_gb: 0}
      }

      assert {:ok, cap2} = Chassis.Inventory.CapacityMap.allocate(cap, %{cpu_cores: 2, ram_gb: 4})
      assert cap2.allocated == %{cpu_cores: 2, ram_gb: 4}

      assert {:error, {:would_overcommit, :cpu_cores}} =
               Chassis.Inventory.CapacityMap.allocate(cap2, %{cpu_cores: 8})
    end

    test "release/2 decrements and clamps to zero" do
      cap = %CapacityMap{
        host_ref: "host:x",
        total: %{cpu_cores: 4},
        allocated: %{cpu_cores: 2}
      }

      assert {:ok, cap2} = Chassis.Inventory.CapacityMap.release(cap, %{cpu_cores: 1})
      assert cap2.allocated == %{cpu_cores: 1}

      assert {:ok, cap3} = Chassis.Inventory.CapacityMap.release(cap2, %{cpu_cores: 99})
      assert cap3.allocated == %{cpu_cores: 0}
    end
  end
end
