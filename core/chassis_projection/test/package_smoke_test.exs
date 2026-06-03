defmodule Chassis.Package.ChassisProjectionTest do
  use ExUnit.Case, async: false

  alias Chassis.Projection.{ChassisDeploymentProjection, Store}

  test "package marker points at reducer logic that rejects unsupported events" do
    {:ok, store} = Chassis.Package.ChassisProjection.store().start_link(name: nil)

    assert Chassis.Package.ChassisProjection.reducer() == ChassisDeploymentProjection

    assert {:error, {:unsupported_projection_event, :unsupported}} =
             ChassisDeploymentProjection.reduce(%{kind: :unsupported, payload: %{}}, store: store)

    assert Store.Memory.list(store) == []
  end
end
