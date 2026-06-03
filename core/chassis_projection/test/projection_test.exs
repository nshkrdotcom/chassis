defmodule Chassis.ProjectionTest do
  use ExUnit.Case, async: false

  alias Chassis.Projection.{ChassisDeploymentProjection, DeploymentStatus, Store}
  alias Chassis.Receipts.DeploymentRecord

  setup do
    {:ok, store} = Store.Memory.start_link(name: nil)
    %{store: store}
  end

  test "reduces deployment receipts into operator-safe deployment projections" do
    record = deployment_record()

    assert %DeploymentStatus{} = projection = ChassisDeploymentProjection.from_receipt(record)
    assert projection.receipt_ref == "receipt:deployment:123"
    assert projection.tenant_ref == "tenant:acme"
    assert projection.installation_ref == "installation:acme:demo"
    assert projection.app_atom == :demo
    assert projection.status == :active
    assert projection.active_profile == "profile:monolith"
    assert projection.trace_id == "trace:phase16:projection"
    assert projection.node_mesh == ["nonode@nohost"]
    assert projection.safe_labels["git_sha"] == "abcdef"
    refute inspect(projection) =~ "raw-secret"
  end

  test "memory projection store upserts by receipt ref and keeps latest per installation", %{
    store: store
  } do
    first = deployment_record(receipt_ref: "receipt:deployment:first", status: :pending)
    second = deployment_record(receipt_ref: "receipt:deployment:second", status: :active)

    assert {:ok, %DeploymentStatus{receipt_ref: "receipt:deployment:first"}} =
             ChassisDeploymentProjection.reduce(%{kind: :chassis_deployment, payload: first},
               store: store
             )

    assert {:ok, %DeploymentStatus{receipt_ref: "receipt:deployment:second"}} =
             ChassisDeploymentProjection.reduce(%{kind: :chassis_deployment, payload: second},
               store: store
             )

    assert {:ok, latest} =
             Store.Memory.latest(store,
               tenant_ref: "tenant:acme",
               installation_ref: "installation:acme:demo"
             )

    assert latest.receipt_ref == "receipt:deployment:second"
    assert latest.status == :active
    assert length(Store.Memory.list(store)) == 2

    assert {:ok, _same} =
             ChassisDeploymentProjection.reduce(%{kind: :chassis_deployment, payload: second},
               store: store
             )

    assert length(Store.Memory.list(store)) == 2
  end

  test "unsupported projection events fail closed without mutating the store", %{store: store} do
    assert {:error, {:unsupported_projection_event, :other}} =
             ChassisDeploymentProjection.reduce(%{kind: :other, payload: %{}}, store: store)

    assert Store.Memory.list(store) == []
  end

  defp deployment_record(overrides \\ []) do
    attrs =
      %{
        receipt_ref: "receipt:deployment:123",
        app_ref: "app:demo:installation:acme:demo:tenant:acme",
        profile_ref: "profile:monolith",
        env: :dev,
        status: :active,
        authority_ref: "authority:decision:phase16",
        tenant_ref: "tenant:acme",
        labels: %{
          "installation_ref" => "installation:acme:demo",
          "app_atom" => "demo",
          "topology_ref" => "topology:profile:monolith",
          "git_sha" => "abcdef",
          "release_version" => "v1",
          "node_mesh" => ["nonode@nohost"],
          "trace_id" => "trace:phase16:projection",
          "secret_token" => "raw-secret"
        },
        written_at: DateTime.utc_now()
      }
      |> Map.merge(Map.new(overrides))

    struct!(DeploymentRecord, attrs)
  end
end
