defmodule Chassis.ContractsTest do
  @moduledoc """
  Phase 1 — `chassis_contracts` hardening tests.

  Per `0541_implementation_readiness_corrections.md` §5, every package phase
  needs happy-path, unhappy-path, lifecycle/idempotency, redaction/boundary,
  and contract tests. This file covers all five categories for the DTO
  structs and behaviour that live in `Chassis.Contracts.*` and
  `NSHKR.Tenant.TenantContext`.

  This file replaces `package_smoke_test.exs` which only asserted that the
  generated marker module loaded. The marker is being removed in this same
  phase per the Phase 0 recovery_baseline §7-§8 schedule.
  """
  use ExUnit.Case, async: true

  alias Chassis.Contracts

  alias Chassis.Contracts.{
    Adapter,
    BEAMNode,
    ComponentManifest,
    ConfigurationProfile,
    EnvironmentResolver,
    HostProvisioningConfig,
    InstallationManifest,
    IsolationProfile,
    PhysicalHost,
    ResidencyContract,
    ServiceSpec,
    StackTopology
  }

  alias NSHKR.Tenant.TenantContext

  describe "struct construction enforces required keys" do
    test "StackTopology requires topology_ref, profile_ref, nodes" do
      assert_raise ArgumentError, ~r/the following keys must also be given/, fn ->
        struct!(StackTopology, %{})
      end

      assert %StackTopology{
               topology_ref: "topology:ext",
               profile_ref: "profile:monolith",
               nodes: []
             } =
               %StackTopology{
                 topology_ref: "topology:ext",
                 profile_ref: "profile:monolith",
                 nodes: []
               }
    end

    test "ServiceSpec requires service_ref, app_ref, runtime_profile_ref, command" do
      assert_raise ArgumentError, fn -> struct!(ServiceSpec, %{}) end

      service =
        %ServiceSpec{
          service_ref: "service:web",
          app_ref: "extravaganza",
          runtime_profile_ref: "runtime:elixir-1.19",
          command: "bin/extravaganza start"
        }

      assert service.service_ref == "service:web"
      assert service.env_files == []
      assert service.args == []
      assert service.ports == []
    end

    test "InstallationManifest requires installation_ref and release_tarball_path" do
      assert_raise ArgumentError, fn -> struct!(InstallationManifest, %{}) end

      manifest = %InstallationManifest{
        installation_ref: "install:extravaganza",
        release_tarball_path: "/opt/nshkr/releases/extravaganza-0.1.0.tar.gz"
      }

      assert manifest.systemd_unit_name == nil
      assert manifest.paths == %{}
      assert manifest.deps == []
      assert manifest.os_packages == []
    end

    test "ComponentManifest requires component_ref, virtual_server, service_specs" do
      assert_raise ArgumentError, fn -> struct!(ComponentManifest, %{}) end

      cm = %ComponentManifest{
        component_ref: "component:vs_app_kit",
        virtual_server: :vs_app_kit,
        service_specs: []
      }

      assert cm.required_capabilities == %{}
    end

    test "TenantContext requires tenant_ref and installation_ref" do
      assert_raise ArgumentError, fn -> struct!(TenantContext, %{}) end

      ctx = %TenantContext{tenant_ref: "tenant:dev", installation_ref: "install:dev"}
      assert ctx.labels == %{}
      assert is_nil(ctx.authority_ref)
    end
  end

  describe "optional struct defaults" do
    test "ConfigurationProfile defaults" do
      p = %ConfigurationProfile{}
      assert p.profile_ref == nil
      assert p.placements == []
    end

    test "PhysicalHost defaults" do
      h = %PhysicalHost{}
      assert h.status == :unknown
      assert h.tenant_refs == []
      assert h.resources == %{}
    end

    test "BEAMNode defaults" do
      n = %BEAMNode{}
      assert n.status == :unknown
      assert n.virtual_servers == []
    end

    test "IsolationProfile defaults to shared" do
      iso = %IsolationProfile{}
      assert iso.compute_isolation == :shared
      assert iso.data_isolation == :row
      assert iso.secrets_isolation == :shared
      assert iso.observability_isolation == :shared_redacted
    end

    test "ResidencyContract empty defaults" do
      r = %ResidencyContract{}
      assert r.allowed_regions == []
      assert r.forbidden_regions == []
      assert r.allowed_providers == []
    end

    test "HostProvisioningConfig defaults" do
      c = %HostProvisioningConfig{}
      assert c.runtime_versions == %{}
      assert c.setup_script == []
      assert c.ufw_ports == []
    end

    test "EnvironmentResolver three-field struct" do
      r = %EnvironmentResolver{
        profile_name: "monolith",
        environment: :dev,
        provisioning_config_ref: "env:local_ubuntu_24_04"
      }

      assert r.environment == :dev
    end
  end

  describe "Chassis.Contracts.encode/1 + decode/1 round-trip" do
    test "StackTopology encodes to canonical JSON and decodes back to a map with string keys" do
      topology = %StackTopology{
        topology_ref: "topology:smoke",
        profile_ref: "profile:monolith",
        tenant_ref: "tenant:acme",
        nodes: [%{"node_ref" => "node:1"}],
        services: [],
        metadata: %{"created_at" => "2026-01-01T00:00:00Z"}
      }

      assert {:ok, json} = Contracts.encode(topology)
      assert is_binary(json)
      assert {:ok, decoded} = Contracts.decode(json)
      assert decoded["topology_ref"] == "topology:smoke"
      assert decoded["profile_ref"] == "profile:monolith"
      assert decoded["tenant_ref"] == "tenant:acme"
      assert decoded["nodes"] == [%{"node_ref" => "node:1"}]
    end

    test "encode/1 is byte-stable for the same struct (canonical key ordering)" do
      topology = %StackTopology{
        topology_ref: "t",
        profile_ref: "p",
        nodes: [],
        metadata: %{"z" => 1, "a" => 2, "m" => 3}
      }

      assert {:ok, j1} = Contracts.encode(topology)
      assert {:ok, j2} = Contracts.encode(topology)
      assert j1 == j2
    end

    test "encode/1 refuses to leak PIDs or references" do
      bad = %{topology_ref: "t", pid: self()}
      assert {:error, _} = Contracts.encode(bad)
    end
  end

  describe "Contracts.encode!/1 refuses unsupported payloads" do
    test "raises on PID-bearing payload" do
      assert_raise ArgumentError, fn -> Contracts.encode!(%{pid: self()}) end
    end
  end

  describe "Chassis.Contracts.redact_tenant_context/1" do
    test "redacts tenant ref to a stable digest token" do
      ctx = %TenantContext{tenant_ref: "tenant:acme:secret", installation_ref: "install:1"}
      redacted = Contracts.redact_tenant_context(ctx)
      assert redacted.tenant_ref != "tenant:acme:secret"
      assert String.starts_with?(redacted.tenant_ref, "tenant:hashed:")
      assert redacted.installation_ref == "install:1"
    end

    test "is idempotent — re-redacting an already-redacted ctx is a no-op" do
      ctx = %TenantContext{tenant_ref: "tenant:acme", installation_ref: "install:1"}
      r1 = Contracts.redact_tenant_context(ctx)
      r2 = Contracts.redact_tenant_context(r1)
      assert r1.tenant_ref == r2.tenant_ref
    end
  end

  describe "Chassis.Contracts.Adapter behaviour contract" do
    defmodule StubAdapter do
      @behaviour Adapter
      @impl true
      def prepare(_payload, _opts), do: {:error, {:not_implemented, __MODULE__}}
      @impl true
      def start(_payload, _opts), do: {:error, {:not_implemented, __MODULE__}}
      @impl true
      def stop(_payload, _opts), do: {:error, {:not_implemented, __MODULE__}}
      @impl true
      def health(_payload, _opts), do: {:error, {:not_implemented, __MODULE__}}
    end

    test "callbacks return the canonical not_implemented tuple" do
      assert {:error, {:not_implemented, StubAdapter}} = StubAdapter.prepare(%{}, [])
      assert {:error, {:not_implemented, StubAdapter}} = StubAdapter.start(%{}, [])
      assert {:error, {:not_implemented, StubAdapter}} = StubAdapter.stop(%{}, [])
      assert {:error, {:not_implemented, StubAdapter}} = StubAdapter.health(%{}, [])
    end

    test "Adapter behaviour defines exactly the four required callbacks" do
      callbacks = Adapter.behaviour_info(:callbacks) |> MapSet.new()

      assert MapSet.new([
               {:prepare, 2},
               {:start, 2},
               {:stop, 2},
               {:health, 2}
             ]) == callbacks
    end
  end

  describe "Inspect redaction" do
    test "TenantContext Inspect implementation masks tenant_ref" do
      ctx = %TenantContext{
        tenant_ref: "tenant:acme:super:secret",
        installation_ref: "install:1",
        authority_ref: "authority:rotate:42"
      }

      inspected = inspect(ctx)
      refute inspected =~ "tenant:acme:super:secret"
      assert inspected =~ "tenant_ref:"
      assert inspected =~ "[REDACTED:tenant"
    end

    test "PhysicalHost Inspect implementation masks ssh_key_ref" do
      h = %PhysicalHost{
        host_ref: "host:1",
        ssh_key_ref: "secret:ssh_key:super:private",
        hostname: "h1"
      }

      inspected = inspect(h)
      refute inspected =~ "super:private"
      assert inspected =~ "ssh_key_ref:"
      assert inspected =~ "[REDACTED"
    end
  end

  describe "JSON round-trip property" do
    @tag :property
    test "ConfigurationProfile round-trips for any well-formed input (smoke)" do
      for placement_count <- [0, 1, 3, 7] do
        placements =
          for i <- 1..placement_count//1 do
            %{
              "node_name_pattern" => "node-#{i}@*",
              "virtual_servers" => ["vs_app_kit", "vs_mezzanine"],
              "required_resources" => %{"cpu" => i, "memory_gb" => i * 2}
            }
          end

        profile = %ConfigurationProfile{
          profile_ref: "profile:test-#{placement_count}",
          name: "test-#{placement_count}",
          placements: placements
        }

        assert {:ok, json} = Contracts.encode(profile)
        assert {:ok, decoded} = Contracts.decode(json)
        assert decoded["profile_ref"] == "profile:test-#{placement_count}"
        assert length(decoded["placements"]) == placement_count
      end
    end
  end
end
