defmodule Chassis.Package.ChassisMezzanineBridgeTest do
  use ExUnit.Case, async: true

  alias Chassis.Mezzanine.Bridge

  test "package marker exposes bridge operations without static success responses" do
    assert :materialize_deployment in Chassis.Package.ChassisMezzanineBridge.operations()

    assert {:error, %Chassis.Boundary.Error{code: :invalid_request}} =
             Bridge.dispatch(:unsupported_operation, %{}, %{})
  end
end
