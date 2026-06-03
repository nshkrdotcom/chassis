defmodule Chassis.Mezzanine.BridgeTest do
  use ExUnit.Case, async: false

  alias Chassis.Boundary
  alias Chassis.Mezzanine.Bridge
  alias Chassis.Mezzanine.Bridge.Outbox
  alias Chassis.Receipts.{DeploymentRecord, Store}

  defmodule RecordingBoundary do
    def dispatch(envelope, opts) do
      send(
        self(),
        {:boundary_dispatch_called, envelope.protocol_ref, Keyword.fetch!(opts, :protocol_module)}
      )

      Chassis.Boundary.dispatch(envelope, opts)
    end
  end

  setup do
    {:ok, receipts_store} = Store.Memory.start_link(name: nil)
    {:ok, registry} = Chassis.AppRegistry.start_link(name: nil)
    {:ok, fence_store} = Chassis.StackManager.FenceStore.start_link(name: nil)
    {:ok, checkpoint_store} = Chassis.StackManager.CheckpointStore.start_link(name: nil)
    {:ok, outbox} = Outbox.start_link(name: nil)

    %{
      receipts_store: receipts_store,
      registry: registry,
      fence_store: fence_store,
      checkpoint_store: checkpoint_store,
      outbox: outbox
    }
  end

  test "materialize deployment dispatches through Chassis.Boundary and publishes a projection event",
       ctx do
    request = %Boundary.MaterializeDeployment.Request{
      topology_ref: "topology:profile:monolith",
      service_spec_ref: "service:demo",
      runtime_profile_ref: "profile:monolith",
      placement_ref: "placement:local",
      environment: :dev,
      git_sha: "abcdef",
      release_version: "v1"
    }

    assert {:ok, %Boundary.Envelope{} = response} =
             Bridge.dispatch(:materialize_deployment, request, envelope_attrs(),
               boundary_dispatcher: RecordingBoundary,
               registry: ctx.registry,
               receipts_store: ctx.receipts_store,
               fence_store: ctx.fence_store,
               outbox: ctx.outbox,
               app_atom: :demo
             )

    assert_receive {:boundary_dispatch_called,
                    "boundary:mezzanine.chassis.materialize_deployment:v1",
                    Chassis.Mezzanine.Bridge.MaterializeDeployment}

    assert response.status == :ok
    assert response.payload.status == :ok
    assert response.payload.deployment_receipt_ref in response.receipt_refs
    assert response.payload.app_ref =~ "app:demo"

    assert {:ok, %DeploymentRecord{} = receipt} =
             Store.Memory.get(ctx.receipts_store, response.payload.deployment_receipt_ref)

    assert receipt.authority_ref == "authority:decision:phase16"

    assert [event] = Outbox.list(ctx.outbox)
    assert event.kind == :chassis_deployment
    assert event.idempotency_key == response.payload.deployment_receipt_ref
    assert event.payload.receipt_ref == response.payload.deployment_receipt_ref
  end

  test "materialize deployment failure returns a boundary error and does not publish outbox",
       ctx do
    request = %Boundary.MaterializeDeployment.Request{
      runtime_profile_ref: "profile:missing",
      environment: :dev
    }

    assert {:error, %Boundary.Error{} = error} =
             Bridge.dispatch(:materialize_deployment, request, envelope_attrs(),
               registry: ctx.registry,
               receipts_store: ctx.receipts_store,
               fence_store: ctx.fence_store,
               outbox: ctx.outbox,
               app_atom: :demo
             )

    assert error.code in [:invalid_request, :non_retryable_failure]
    assert Outbox.list(ctx.outbox) == []
  end

  test "rollback dispatch uses real StackManager rollback and emits rollback response", ctx do
    app_ref = "app:demo:installation:acme:demo:tenant:dev"
    current = deployment_record("receipt:deployment:current", :active)
    target = deployment_record("receipt:deployment:previous", :active)
    {:ok, _} = Store.Memory.put(ctx.receipts_store, current)
    {:ok, _} = Store.Memory.put(ctx.receipts_store, target)

    {:ok, entry} =
      Chassis.AppRegistry.Entry.new(%{
        app_ref: app_ref,
        app_atom: :demo,
        installation_ref: "installation:acme:demo",
        tenant_ref: "tenant:dev",
        active_profile: "profile:monolith",
        environment: :dev,
        git_sha: "abcdef",
        release_version: "v2",
        node_mesh: [node()],
        status: :active,
        last_deployment_receipt_ref: current.receipt_ref,
        rollback_target_ref: target.receipt_ref
      })

    {:ok, _} = Chassis.AppRegistry.register(ctx.registry, entry)

    request = %Boundary.RollbackDeployment.Request{
      deployment_receipt_ref: current.receipt_ref,
      rollback_ref: "rollback:phase16",
      reason: "operator",
      target_revision: "previous"
    }

    assert {:ok, %Boundary.Envelope{} = response} =
             Bridge.dispatch(:rollback_deployment, request, envelope_attrs(),
               registry: ctx.registry,
               receipts_store: ctx.receipts_store,
               checkpoint_store: ctx.checkpoint_store,
               app_ref: app_ref
             )

    assert response.payload.status == "rolled_back"
    assert response.payload.rollback_receipt_ref in response.receipt_refs
  end

  test "inspect, validate, drain, and provision operations execute concrete handlers" do
    assert {:ok, inspect_response} =
             Bridge.dispatch(
               :inspect_host,
               %Boundary.InspectHost.Request{host_ref: "host:local"},
               read_envelope_attrs(),
               hosts: [%{host_ref: "host:local", status: :online, facts: %{cpu: 8}}]
             )

    assert inspect_response.payload.status == "online"
    assert inspect_response.payload.facts.cpu == 8

    assert {:ok, validate_response} =
             Bridge.dispatch(
               :validate_topology,
               %Boundary.ValidateTopology.Request{
                 topology_ref: "topology:valid",
                 topology: %{assignments: [%{node: "app"}]},
                 profile: %{profile_ref: "profile:monolith"}
               },
               envelope_attrs()
             )

    assert validate_response.payload.valid? == "true"

    assert {:ok, drain_response} =
             Bridge.dispatch(
               :drain_host,
               %Boundary.DrainHost.Request{host_ref: "host:local", reason: "maintenance"},
               envelope_attrs(),
               drain_host: fn request ->
                 {:ok, %{host_ref: request.host_ref, status: :drained}}
               end
             )

    assert drain_response.payload.status == "drained"

    assert {:ok, provision_response} =
             Bridge.dispatch(
               :provision_host,
               %Boundary.ProvisionHost.Request{
                 host_ref: "host:local",
                 profile_ref: "profile:dev"
               },
               envelope_attrs(),
               provision_host: fn request ->
                 {:ok,
                  %{
                    host_ref: request.host_ref,
                    provisioning_receipt_ref: "receipt:provisioning:1",
                    status: :ok
                  }}
               end
             )

    assert provision_response.payload.provisioning_receipt_ref == "receipt:provisioning:1"
  end

  test "outbox enqueue is idempotent and drain marks delivered only after publisher success",
       ctx do
    event = %{
      kind: :chassis_deployment,
      payload: %{receipt_ref: "receipt:deployment:1", tenant_ref: "tenant:dev"},
      idempotency_key: "receipt:deployment:1"
    }

    assert {:ok, first} = Outbox.enqueue(ctx.outbox, event)
    assert {:ok, ^first} = Outbox.enqueue(ctx.outbox, event)
    assert length(Outbox.list(ctx.outbox)) == 1

    assert {:error, {:drain_failed, _event, :mezzanine_down}} =
             Outbox.drain(ctx.outbox, publisher: fn _event -> {:error, :mezzanine_down} end)

    assert [%{status: :pending}] = Outbox.list(ctx.outbox)

    assert {:ok, %{delivered: 1}} =
             Outbox.drain(ctx.outbox,
               publisher: fn published ->
                 send(self(), {:published, published.payload.receipt_ref})
                 :ok
               end
             )

    assert_receive {:published, "receipt:deployment:1"}
    assert [%{status: :delivered}] = Outbox.list(ctx.outbox)
  end

  test "evolution failure batch boundary publishes typed outbox entry", ctx do
    {:ok, receipts_store} = Chassis.Evolution.Receipts.Store.Memory.start_link(name: nil)

    assert {:ok, response} =
             Bridge.dispatch(
               :create_failure_batch,
               %{
                 "tenant_ref" => "tenant:dev",
                 "installation_ref" => "installation:acme:demo",
                 "evidence_refs" => ["ev:smoke:1"],
                 "summary" => %{"bytes" => "bounded smoke", "max_bytes" => 128},
                 "redaction_posture" => "default",
                 "raw_body" => "RAW SECRET"
               },
               envelope_attrs(),
               boundary_dispatcher: Chassis.Mezzanine.Bridge.Evolution.LocalDispatcher,
               receipts_store: receipts_store,
               outbox: ctx.outbox
             )

    assert %{
             failure_batch_ref: failure_batch_ref,
             receipt_ref: receipt_ref,
             status: "ok"
           } = response.payload

    assert failure_batch_ref =~ "failure-batch:"
    assert receipt_ref =~ "receipt:failure_batch:"

    assert [%Outbox.Entry{} = event] = Outbox.list(ctx.outbox)
    assert event.projection == :chassis_evolution
    assert event.primary_ref == failure_batch_ref
    assert event.payload.failure_batch_ref == failure_batch_ref
    assert event.payload.receipt_ref == receipt_ref
    refute inspect(event) =~ "RAW SECRET"
  end

  defp envelope_attrs do
    %{
      envelope_ref: "env:phase16:" <> unique(),
      tenant_ref: "tenant:dev",
      installation_ref: "installation:acme:demo",
      actor_ref: "actor:operator",
      authority_ref: "authority:decision:phase16",
      idempotency_key: "idem:" <> unique(),
      trace_id: "trace:phase16"
    }
  end

  defp read_envelope_attrs do
    envelope_attrs()
    |> Map.delete(:authority_ref)
    |> Map.delete(:idempotency_key)
  end

  defp deployment_record(ref, status) do
    %DeploymentRecord{
      receipt_ref: ref,
      app_ref: "app:demo:installation:acme:demo:tenant:dev",
      profile_ref: "profile:monolith",
      env: :dev,
      status: status,
      authority_ref: "authority:decision:phase16",
      tenant_ref: "tenant:dev"
    }
  end

  defp unique, do: System.unique_integer([:positive]) |> Integer.to_string()
end
