defmodule Chassis.StackManagerTenantGuardTest do
  use ExUnit.Case, async: true

  alias Chassis.AppRegistry
  alias Chassis.Receipts.{DeploymentRecord, Store}
  alias Chassis.StackManager.{FenceStore, Transaction}

  setup do
    %{
      registry: start_supervised!({AppRegistry, name: nil}),
      receipts: start_supervised!({Store.Memory, name: nil}),
      fence_store: start_supervised!({FenceStore, name: nil})
    }
  end

  test "missing tenant context is rejected before deployment side effects", ctx do
    parent = self()

    assert {:error, {:tenant_context_required, [:tenant_ref]}} =
             Transaction.run(
               profile_ref: "profile:ternary-split-3",
               env: :dev,
               app_atom: :extravaganza,
               installation_ref: "installation:default",
               idempotency_key: "missing-tenant",
               registry: ctx.registry,
               receipts_store: ctx.receipts,
               fence_store: ctx.fence_store,
               discover_hosts: fn ->
                 send(parent, :discover_hosts_called)
                 {:ok, []}
               end,
               provision: fn _ ->
                 send(parent, :provision_called)
                 {:ok, :bad}
               end
             )

    refute_receive :discover_hosts_called
    refute_receive :provision_called
    assert {:ok, []} = AppRegistry.list(ctx.registry, [])
    assert Store.Memory.list(ctx.receipts, kind: DeploymentRecord) == []
  end

  test "residency and quota guards run before authorize provision mesh registry and receipts",
       ctx do
    parent = self()

    assert {:error, {:topology_invalid, errors}} =
             Transaction.run(
               profile_ref: "profile:monolith",
               env: :prod,
               app_atom: :extravaganza,
               tenant_ref: "tenant:acme",
               installation_ref: "installation:acme:extravaganza",
               residency_ref: "residency:us-only",
               isolation_profile_ref: "isolation:shared-standard",
               quota_ref: "quota:tenant:enterprise",
               idempotency_key: "residency-denied",
               registry: ctx.registry,
               receipts_store: ctx.receipts,
               fence_store: ctx.fence_store,
               discover_hosts: fn ->
                 {:ok,
                  [
                    host("host:app", "appkit@fsn1", "fsn1", %{cpu_cores: 4, ram_gb: 8, gpus: 0}),
                    host("host:control", "control@fsn1", "fsn1", %{
                      cpu_cores: 8,
                      ram_gb: 32,
                      gpus: 0
                    }),
                    host("host:data", "data@fsn1", "fsn1", %{cpu_cores: 16, ram_gb: 64, gpus: 0})
                  ]}
               end,
               authorize: fn _ ->
                 send(parent, :authorize_called)
                 {:ok, "authority:bad"}
               end,
               provision: fn _ ->
                 send(parent, :provision_called)
                 {:ok, :bad}
               end,
               mesh_join: fn _ ->
                 send(parent, :mesh_called)
                 {:ok, []}
               end
             )

    assert Enum.any?(errors, &(&1.code == :residency_violation))
    refute_receive :authorize_called
    refute_receive :provision_called
    refute_receive :mesh_called
    assert {:ok, []} = AppRegistry.list(ctx.registry, [])
    assert Store.Memory.list(ctx.receipts, kind: DeploymentRecord) == []
  end

  test "quota denial prevents provisioning side effects", ctx do
    parent = self()

    assert {:error, {:quota_exceeded, %{reason: :gpu_quota_exceeded}}} =
             Transaction.run(
               profile_ref: "profile:monolith",
               env: :prod,
               app_atom: :stack_coder,
               tenant_ref: "tenant:acme",
               installation_ref: "installation:acme:stack-coder",
               residency_ref: "residency:global",
               isolation_profile_ref: "isolation:shared-standard",
               quota_ref: "quota:tenant:starter",
               idempotency_key: "quota-denied",
               registry: ctx.registry,
               receipts_store: ctx.receipts,
               fence_store: ctx.fence_store,
               requested_resources: %{cpu_cores: 1, ram_gb: 1, gpus: 1},
               discover_hosts: fn ->
                 {:ok,
                  [
                    host("host:gpu", "monolith@local", "local", %{
                      cpu_cores: 16,
                      ram_gb: 64,
                      gpus: 2
                    })
                  ]}
               end,
               provision: fn _ ->
                 send(parent, :provision_called)
                 {:ok, :bad}
               end
             )

    refute_receive :provision_called
    assert {:ok, []} = AppRegistry.list(ctx.registry, [])
    assert Store.Memory.list(ctx.receipts, kind: DeploymentRecord) == []
  end

  defp host(ref, hostname, region, resources) do
    %{
      host_ref: ref,
      provider: :hetzner,
      region: region,
      hostname: hostname,
      resources: resources,
      tenant_refs: []
    }
  end
end
