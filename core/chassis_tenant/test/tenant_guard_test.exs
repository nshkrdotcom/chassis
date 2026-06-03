defmodule Chassis.TenantGuardTest do
  use ExUnit.Case, async: false

  alias Chassis.Tenant.{
    GuardSupervisor,
    Isolation,
    Observability,
    Quota,
    QuotaConsumptionTracker,
    QuotaGuard,
    Residency,
    TopologyGuard
  }

  test "residency:us-only rejects EU-only hosts" do
    {:ok, residency} = Residency.Catalog.fetch("residency:us-only")
    {:ok, isolation} = Isolation.Catalog.fetch("isolation:shared-standard")
    {:ok, quota} = Quota.Catalog.fetch("quota:tenant:enterprise")

    assert {:ok, %{valid?: false, errors: errors}} =
             TopologyGuard.validate(%{
               profile: profile([placement("appkit@*", %{cpu_cores: 2, ram_gb: 4, gpus: 0})]),
               tenant_ref: "tenant:acme",
               installation_ref: "installation:acme:extravaganza",
               residency_contract: residency,
               isolation_profile: isolation,
               resource_quota: quota,
               hosts: [
                 %{
                   host_ref: "host:fsn1",
                   provider: :hetzner,
                   region: "fsn1",
                   hostname: "appkit@fsn1",
                   resources: %{cpu_cores: 4, ram_gb: 8, gpus: 0}
                 }
               ]
             })

    assert Enum.any?(errors, &(&1.code == :residency_violation))
  end

  test "dedicated-node isolation rejects hosts already assigned to another tenant" do
    {:ok, residency} = Residency.Catalog.fetch("residency:global")
    {:ok, isolation} = Isolation.Catalog.fetch("isolation:dedicated-gpu")
    {:ok, quota} = Quota.Catalog.fetch("quota:tenant:enterprise")

    assert {:ok, %{valid?: false, errors: errors}} =
             TopologyGuard.validate(%{
               profile: profile([placement("monolith@*", %{cpu_cores: 4, ram_gb: 8, gpus: 1})]),
               tenant_ref: "tenant:acme",
               installation_ref: "installation:acme:stack-coder",
               residency_contract: residency,
               isolation_profile: isolation,
               resource_quota: quota,
               hosts: [
                 %{
                   host_ref: "host:shared-gpu",
                   provider: :local,
                   region: "local",
                   hostname: "monolith@local",
                   tenant_refs: ["tenant:other"],
                   resources: %{cpu_cores: 16, ram_gb: 64, gpus: 2}
                 }
               ]
             })

    assert Enum.any?(errors, &(&1.code == :isolation_violation))
  end

  test "quota guard rejects cpu and gpu overages with safe decisions" do
    {:ok, quota} = Quota.Catalog.fetch("quota:tenant:starter")

    assert {:ok, %{allowed?: false, reason: :cpu_quota_exceeded, safe_message: msg}} =
             QuotaGuard.check(quota, %{cpu_cores: 9, gpus: 0, ram_gb: 1})

    assert msg =~ "CPU"

    assert {:ok, %{allowed?: false, reason: :gpu_quota_exceeded, safe_message: msg}} =
             QuotaGuard.check(quota, %{cpu_cores: 1, gpus: 1, ram_gb: 1})

    assert msg =~ "GPU"
  end

  test "guard supervisor tracks consumption used by quota decisions" do
    start_supervised!(GuardSupervisor)
    {:ok, quota} = Quota.Catalog.fetch("quota:tenant:starter")

    assert :ok = QuotaConsumptionTracker.put("tenant:acme", %{cpu_cores: 7, gpus: 0, ram_gb: 1})

    assert {:ok, %{allowed?: false, reason: :cpu_quota_exceeded}} =
             QuotaGuard.check(%{quota | tenant_ref: "tenant:acme"}, %{
               cpu_cores: 2,
               gpus: 0,
               ram_gb: 1
             })
  end

  test "topology guard fails closed when required tenant context is missing" do
    {:ok, residency} = Residency.Catalog.fetch("residency:global")
    {:ok, isolation} = Isolation.Catalog.fetch("isolation:dev-shared")
    {:ok, quota} = Quota.Catalog.fetch("quota:tenant:dev")

    assert {:ok, %{valid?: false, errors: errors}} =
             TopologyGuard.validate(%{
               profile: profile([placement("monolith@*", %{cpu_cores: 1, ram_gb: 1, gpus: 0})]),
               installation_ref: "installation:missing-tenant",
               residency_contract: residency,
               isolation_profile: isolation,
               resource_quota: quota,
               hosts: [
                 %{
                   host_ref: "host:local",
                   region: "local",
                   resources: %{cpu_cores: 2, ram_gb: 2, gpus: 0}
                 }
               ]
             })

    assert Enum.any?(errors, &(&1.code == :tenant_context_required))
  end

  test "shared-redacted observability labels hash tenant refs" do
    {:ok, shared} = Isolation.Catalog.fetch("isolation:dev-shared")
    {:ok, partitioned} = Isolation.Catalog.fetch("isolation:shared-standard")

    redacted = Observability.tenant_label("tenant:acme", shared)

    assert redacted =~ "tenant_hash:"
    refute redacted =~ "tenant:acme"
    assert Observability.tenant_label("tenant:acme", partitioned) == "tenant:acme"
  end

  defp profile(placements), do: %{profile_ref: "profile:test", placements: placements}

  defp placement(pattern, resources) do
    %{
      node_name_pattern: pattern,
      virtual_servers: [:vs_app_kit],
      required_resources: resources
    }
  end
end
