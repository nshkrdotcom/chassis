defmodule Chassis.Adapter.TofuTest do
  use ExUnit.Case, async: true
  alias Chassis.Adapter.Tofu

  test "Plan struct enforces plan_ref and workspace_ref" do
    assert_raise ArgumentError, fn -> struct!(Tofu.Plan, %{}) end

    p = %Tofu.Plan{plan_ref: "plan:1", workspace_ref: "ws:demo"}
    assert p.changes == []
  end

  test "Apply struct enforces apply_ref, plan_ref, status" do
    assert_raise ArgumentError, fn -> struct!(Tofu.Apply, %{}) end

    a = %Tofu.Apply{apply_ref: "a:1", plan_ref: "plan:1", status: :ok}
    assert a.results == []
  end

  test "plan/1 returns canonical not_implemented" do
    assert {:error, {:not_implemented, Chassis.Adapter.Tofu}} = Tofu.plan(%{})
  end

  test "apply/1 returns canonical not_implemented for either DTO or map input" do
    plan = %Tofu.Plan{plan_ref: "p", workspace_ref: "w"}
    assert {:error, {:not_implemented, Chassis.Adapter.Tofu}} = Tofu.apply(plan)
    assert {:error, {:not_implemented, Chassis.Adapter.Tofu}} = Tofu.apply(%{})
  end
end
