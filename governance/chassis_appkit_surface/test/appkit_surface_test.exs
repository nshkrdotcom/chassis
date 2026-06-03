defmodule Chassis.AppKit.SurfaceTest do
  use ExUnit.Case, async: true

  alias Chassis.AppKit.Surface

  test "projection structs validate required deployment readback fields" do
    assert {:ok, projection} =
             Surface.Projection.new(%{
               deployment_ref: "deployment:demo",
               app_ref: "app:demo:installation:acme:demo:tenant:dev",
               app_atom: :demo,
               tenant_ref: "tenant:dev",
               installation_ref: "installation:acme:demo",
               active_profile: "profile:monolith",
               health_status: :healthy,
               receipt_ref: "receipt:deployment:1",
               status: :active
             })

    assert projection.active_profile == "profile:monolith"
    assert projection.health_status == :healthy
  end

  test "projection validation fails closed without profile context" do
    assert {:error, %Surface.Error{code: :invalid_projection, safe_message: message}} =
             Surface.Projection.new(%{app_ref: "app:demo"})

    assert message =~ "active_profile"
  end

  test "package marker exposes schema modules without static implemented flag" do
    assert Chassis.Package.AppkitSurface.package_ref() == "chassis_appkit_surface"
    assert Chassis.Package.AppkitSurface.projection_module() == Surface.Projection
    assert Chassis.Package.AppkitSurface.error_module() == Surface.Error
  end
end
