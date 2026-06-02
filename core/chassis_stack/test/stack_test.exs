defmodule Chassis.StackTest do
  @moduledoc """
  Phase 5 — `chassis_stack` virtual-to-physical mapping tests.

  Covers the four canonical profiles, the dev/prod adapter resolution, the
  placement planner (which must consult capacity constraints, not blindly
  round-robin), and the Composer end-to-end.
  """
  use ExUnit.Case, async: true

  alias Chassis.Stack.{Composer, ConfigurationProfile, PlacementPlanner, ProfileResolver}

  describe "ConfigurationProfile registry — all four canonical profiles" do
    test "all/0 lists every documented profile" do
      keys = Map.keys(ConfigurationProfile.all())
      assert "profile:monolith" in keys
      assert "profile:decoupled-cockpit-2" in keys
      assert "profile:ternary-split-3" in keys
      assert "profile:maximal-decoupled" in keys
    end

    test "profile:monolith has exactly one placement with all virtual servers" do
      {:ok, p} = ConfigurationProfile.get("profile:monolith")
      assert [single] = p.placements
      assert :vs_app_kit in single.virtual_servers
      assert :vs_mezzanine in single.virtual_servers
      assert :vs_outer_brain in single.virtual_servers
      assert :vs_citadel in single.virtual_servers
      assert :vs_jido_integration in single.virtual_servers
      assert :vs_execution_plane in single.virtual_servers
      assert :vs_secrets_plane in single.virtual_servers
      assert :vs_observability in single.virtual_servers
    end

    test "profile:ternary-split-3 has exactly three placements covering disjoint VS subsets" do
      {:ok, p} = ConfigurationProfile.get("profile:ternary-split-3")
      assert length(p.placements) == 3

      all_vs = Enum.flat_map(p.placements, & &1.virtual_servers)
      assert length(Enum.uniq(all_vs)) == length(all_vs), "virtual_servers must be disjoint"
    end

    test "profile:maximal-decoupled has one placement per virtual server (8 total)" do
      {:ok, p} = ConfigurationProfile.get("profile:maximal-decoupled")
      assert length(p.placements) == 8
      Enum.each(p.placements, fn pl -> assert length(pl.virtual_servers) == 1 end)
    end

    test "get/1 unknown profile returns {:error, :unknown_profile}" do
      assert {:error, :unknown_profile} = ConfigurationProfile.get("profile:nope")
    end
  end

  describe "ProfileResolver.resolve/2 dev vs prod adapter sets" do
    test "dev resolves to local-loopback adapter set" do
      assert {:ok, resolved} = ProfileResolver.resolve("profile:monolith", :dev)
      assert resolved.env == :dev
      assert resolved.adapters.discovery == :static
      assert resolved.adapters.provisioning == :local_noop
      assert resolved.adapters.secrets == :env
      assert resolved.adapters.mesh == :local_loopback
    end

    test "prod resolves to ssh + sops + tls adapter set" do
      assert {:ok, resolved} = ProfileResolver.resolve("profile:ternary-split-3", :prod)
      assert resolved.env == :prod
      assert resolved.adapters.discovery == :dynamic
      assert resolved.adapters.provisioning == :ssh_bootstrap
      assert resolved.adapters.secrets == :sops
      assert resolved.adapters.mesh == :beam_tls
    end

    test "every profile × env resolves to a usable map (8 combos total)" do
      profiles = [
        "profile:monolith",
        "profile:decoupled-cockpit-2",
        "profile:ternary-split-3",
        "profile:maximal-decoupled"
      ]

      for prof <- profiles, env <- [:dev, :prod] do
        assert {:ok, r} = ProfileResolver.resolve(prof, env)
        assert r.profile_ref == prof
        assert is_list(r.placements)
      end
    end

    test "unknown profile fails resolve/2 with the same shape as get/1" do
      assert {:error, :unknown_profile} = ProfileResolver.resolve("profile:nope", :dev)
    end

    test "unsupported environment is rejected" do
      assert {:error, {:unknown_environment, :staging}} =
               ProfileResolver.resolve("profile:monolith", :staging)
    end
  end

  describe "PlacementPlanner.plan/2 — capacity-aware assignment" do
    setup do
      %{
        big_host: %{host_ref: "host:big", resources: %{cpu_cores: 32, ram_gb: 128, gpus: 4}},
        small_host: %{host_ref: "host:small", resources: %{cpu_cores: 2, ram_gb: 4, gpus: 0}}
      }
    end

    test "assigns each placement to a host that has enough capacity", %{big_host: big, small_host: small} do
      {:ok, profile} = ConfigurationProfile.get("profile:ternary-split-3")
      assert {:ok, assignments} = PlacementPlanner.plan(profile, [big, small])

      Enum.each(assignments, fn a ->
        assert is_binary(a.host_ref)
        required = Map.get(a, :required_resources, %{})
        host = if a.host_ref == "host:big", do: big, else: small
        cpu_ok = Map.get(required, :cpu_cores, 0) <= host.resources.cpu_cores
        ram_ok = Map.get(required, :ram_gb, 0) <= host.resources.ram_gb
        gpu_ok = Map.get(required, :gpus, 0) <= host.resources.gpus
        assert cpu_ok and ram_ok and gpu_ok, "placement #{inspect(a)} does not fit host #{a.host_ref}"
      end)
    end

    test "returns {:error, :insufficient_capacity} when no host can host a placement", %{small_host: small} do
      {:ok, profile} = ConfigurationProfile.get("profile:ternary-split-3")
      # the 'data@' placement requires cpu_cores: 8 which small_host cannot satisfy
      assert {:error, {:insufficient_capacity, _placement}} = PlacementPlanner.plan(profile, [small])
    end

    test "returns {:error, :no_hosts} when host list is empty" do
      {:ok, profile} = ConfigurationProfile.get("profile:monolith")
      assert {:error, :no_hosts} = PlacementPlanner.plan(profile, [])
    end
  end

  describe "Composer.compose/3 end-to-end" do
    setup do
      %{
        hosts: [
          %{host_ref: "host:big-1", resources: %{cpu_cores: 32, ram_gb: 128, gpus: 4}},
          %{host_ref: "host:big-2", resources: %{cpu_cores: 32, ram_gb: 128, gpus: 4}},
          %{host_ref: "host:big-3", resources: %{cpu_cores: 32, ram_gb: 128, gpus: 4}}
        ]
      }
    end

    test "produces a topology containing assignments and the resolved adapter set", %{hosts: hosts} do
      assert {:ok, topology} = Composer.compose("profile:ternary-split-3", :prod, hosts)
      assert topology.topology_ref == "topology:profile:ternary-split-3"
      assert topology.profile_ref == "profile:ternary-split-3"
      assert topology.env == :prod
      assert length(topology.assignments) == 3
      assert topology.adapters.provisioning == :ssh_bootstrap
    end

    test "compose/3 propagates :unknown_profile errors", %{hosts: hosts} do
      assert {:error, :unknown_profile} = Composer.compose("profile:nope", :dev, hosts)
    end

    test "compose/3 propagates :no_hosts errors" do
      assert {:error, :no_hosts} = Composer.compose("profile:monolith", :dev, [])
    end
  end

  describe "spine audit: node_name_pattern uses Atom.to_string ++ '@*' style, never case node()" do
    test "every placement pattern looks like '<word>@*' (substring match), not a case-clause" do
      profiles = ConfigurationProfile.all()

      Enum.each(profiles, fn {_ref, placements} ->
        Enum.each(placements, fn pl ->
          assert pl.node_name_pattern =~ ~r/^[a-z_]+@\*$/,
                 "non-pattern node_name_pattern: #{pl.node_name_pattern}"
        end)
      end)
    end

    test "Chassis.Stack source contains no 'case node()' branching outside the @moduledoc" do
      source = File.read!(Path.join(File.cwd!(), "lib/chassis/stack.ex"))
      # strip moduledocs / docs before scanning
      stripped = Regex.replace(~r/@moduledoc\s+"""[\s\S]*?"""/m, source, "")
      refute stripped =~ "case node()"
    end
  end
end
