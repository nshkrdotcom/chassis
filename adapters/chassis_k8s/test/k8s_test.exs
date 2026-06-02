defmodule Chassis.Adapter.K8sTest do
  use ExUnit.Case, async: true
  alias Chassis.Adapter.K8s

  test "Manifest struct enforces api_version, kind, metadata" do
    assert_raise ArgumentError, fn -> struct!(K8s.Manifest, %{}) end

    m = %K8s.Manifest{
      api_version: "apps/v1",
      kind: "Deployment",
      metadata: %{"name" => "demo"}
    }

    assert m.spec == %{}
  end

  test "apply/1 returns canonical not_implemented" do
    assert {:error, {:not_implemented, Chassis.Adapter.K8s}} = K8s.apply(%{})
  end

  test "delete/1 returns canonical not_implemented" do
    assert {:error, {:not_implemented, Chassis.Adapter.K8s}} = K8s.delete(%{})
  end
end
