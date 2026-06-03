defmodule Chassis.StackManagerTest do
  use ExUnit.Case, async: true

  alias Chassis.AppRegistry
  alias Chassis.AppRegistry.Entry
  alias Chassis.Receipts.{DeploymentRecord, RollbackRecord, Store}
  alias Chassis.StackManager.{CheckpointStore, FenceStore, Transaction}

  setup do
    registry = start_supervised!({AppRegistry, name: nil})
    receipts = start_supervised!({Store.Memory, name: nil})
    fence_store = start_supervised!({FenceStore, name: nil})
    checkpoint_store = start_supervised!({CheckpointStore, name: nil})

    %{
      registry: registry,
      receipts: receipts,
      fence_store: fence_store,
      checkpoint_store: checkpoint_store,
      host: %{
        host_ref: "host:local",
        resources: %{cpu_cores: 8, ram_gb: 32, gpus: 0, disk_gb: 500}
      }
    }
  end

  test "Transaction.run executes every deployment step, writes a receipt, and registers the app",
       ctx do
    parent = self()

    assert {:ok, result} =
             Transaction.run(
               profile_ref: "profile:monolith",
               env: :dev,
               app_atom: :extravaganza,
               tenant_ref: "tenant:dev",
               installation_ref: "installation:default",
               git_sha: "abc123",
               release_version: "v1",
               idempotency_key: "deploy-one",
               registry: ctx.registry,
               receipts_store: ctx.receipts,
               fence_store: ctx.fence_store,
               discover_hosts: fn ->
                 send(parent, :discover_hosts)
                 {:ok, [ctx.host]}
               end,
               authorize: fn attrs ->
                 send(parent, {:authorize, attrs.profile_ref})
                 {:ok, "authority:ok"}
               end,
               provision: fn topology ->
                 send(parent, {:provision, topology.profile_ref})
                 {:ok, :provisioned}
               end,
               mesh_join: fn topology ->
                 send(parent, {:mesh_join, topology.profile_ref})
                 {:ok, [:node@host]}
               end
             )

    assert result.status == :active
    assert result.steps == Transaction.steps()
    assert result.receipt_ref =~ "receipt:deployment:"
    refute result.receipt_ref == "receipt:deployment:smoke"
    assert result.fence_ref =~ "fence:chassis.deploy:"
    assert result.authority_ref == "authority:ok"

    assert_receive :discover_hosts
    assert_receive {:authorize, "profile:monolith"}
    assert_receive {:provision, "profile:monolith"}
    assert_receive {:mesh_join, "profile:monolith"}

    assert {:ok, %Entry{} = entry} = AppRegistry.lookup(ctx.registry, result.app_ref)
    assert entry.active_profile == "profile:monolith"
    assert entry.last_deployment_receipt_ref == result.receipt_ref

    assert {:ok, %DeploymentRecord{} = receipt} =
             Store.Memory.get(ctx.receipts, result.receipt_ref)

    assert receipt.app_ref == result.app_ref
    assert receipt.profile_ref == "profile:monolith"
    assert receipt.authority_ref == "authority:ok"
  end

  test "idempotency returns the existing result and does not run side effects twice", ctx do
    counter = :counters.new(1, [])

    opts = [
      profile_ref: "profile:monolith",
      env: :dev,
      app_atom: :extravaganza,
      tenant_ref: "tenant:dev",
      installation_ref: "installation:default",
      git_sha: "abc123",
      release_version: "v1",
      idempotency_key: "same-key",
      registry: ctx.registry,
      receipts_store: ctx.receipts,
      fence_store: ctx.fence_store,
      discover_hosts: fn -> {:ok, [ctx.host]} end,
      authorize: fn _ -> {:ok, "authority:ok"} end,
      provision: fn _ ->
        :counters.add(counter, 1, 1)
        {:ok, :provisioned}
      end,
      mesh_join: fn _ -> {:ok, [:node@host]} end
    ]

    assert {:ok, first} = Transaction.run(opts)
    assert {:ok, second} = Transaction.run(opts)
    assert first.receipt_ref == second.receipt_ref
    assert second.idempotent? == true
    assert :counters.get(counter, 1) == 1
  end

  test "authority failure is fail-closed before provision, mesh, registry, or receipts side effects",
       ctx do
    parent = self()

    assert {:error, {:authority_denied, :policy}} =
             Transaction.run(
               profile_ref: "profile:monolith",
               env: :dev,
               app_atom: :extravaganza,
               tenant_ref: "tenant:dev",
               installation_ref: "installation:default",
               git_sha: "abc123",
               release_version: "v1",
               idempotency_key: "denied",
               registry: ctx.registry,
               receipts_store: ctx.receipts,
               fence_store: ctx.fence_store,
               discover_hosts: fn -> {:ok, [ctx.host]} end,
               authorize: fn _ -> {:error, {:authority_denied, :policy}} end,
               provision: fn _ ->
                 send(parent, :provision_called)
                 {:ok, :bad}
               end,
               mesh_join: fn _ ->
                 send(parent, :mesh_called)
                 {:ok, []}
               end
             )

    refute_receive :provision_called
    refute_receive :mesh_called
    assert {:ok, []} = AppRegistry.list(ctx.registry, [])
    assert Store.Memory.list(ctx.receipts, kind: DeploymentRecord) == []
  end

  test "rollback uses checkpoints and updates the registry rollback pointer", ctx do
    {:ok, deploy_v1} = deploy(ctx, "profile:monolith", "v1", "k1")
    {:ok, deploy_v2} = deploy(ctx, "profile:ternary-split-3", "v2", "k2")

    assert {:ok, entry_v2} = AppRegistry.lookup(ctx.registry, deploy_v2.app_ref)
    assert entry_v2.rollback_target_ref == deploy_v1.receipt_ref

    parent = self()

    assert {:ok, rollback} =
             Transaction.rollback(deploy_v2.app_ref,
               registry: ctx.registry,
               receipts_store: ctx.receipts,
               checkpoint_store: ctx.checkpoint_store,
               rollback_node: fn node ->
                 send(parent, {:rolled_back_node, node})
                 :ok
               end
             )

    assert rollback.status == :rolled_back
    assert rollback.rollback_target_ref == deploy_v1.receipt_ref
    assert_receive {:rolled_back_node, :node@host}

    assert {:ok, %RollbackRecord{} = rollback_receipt} =
             Store.Memory.get(ctx.receipts, rollback.rollback_receipt_ref)

    assert rollback_receipt.deployment_receipt_ref == deploy_v2.receipt_ref

    assert {:ok, rolled_entry} = AppRegistry.lookup(ctx.registry, deploy_v2.app_ref)
    assert rolled_entry.status == :active
    assert rolled_entry.last_deployment_receipt_ref == deploy_v1.receipt_ref
    assert rolled_entry.active_profile == "profile:monolith"
  end

  defp deploy(ctx, profile, version, key) do
    Transaction.run(
      profile_ref: profile,
      env: :dev,
      app_atom: :extravaganza,
      tenant_ref: "tenant:dev",
      installation_ref: "installation:default",
      git_sha: "abc123",
      release_version: version,
      idempotency_key: key,
      registry: ctx.registry,
      receipts_store: ctx.receipts,
      fence_store: ctx.fence_store,
      discover_hosts: fn -> {:ok, hosts_for(profile, ctx.host)} end,
      authorize: fn _ -> {:ok, "authority:ok"} end,
      provision: fn _ -> {:ok, :provisioned} end,
      mesh_join: fn _ -> {:ok, [:node@host]} end
    )
  end

  defp hosts_for("profile:ternary-split-3", _host) do
    [
      %{host_ref: "host:app", resources: %{cpu_cores: 2, ram_gb: 4, gpus: 0, disk_gb: 100}},
      %{host_ref: "host:control", resources: %{cpu_cores: 4, ram_gb: 16, gpus: 0, disk_gb: 100}},
      %{host_ref: "host:data", resources: %{cpu_cores: 8, ram_gb: 32, gpus: 0, disk_gb: 100}}
    ]
  end

  defp hosts_for(_profile, host), do: [host]
end
