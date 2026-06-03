defmodule Chassis.Package.AppkitSurface.SmokeTest do
  use ExUnit.Case, async: true

  test "package marker exposes projection construction" do
    assert {:ok, projection} =
             Chassis.Package.AppkitSurface.projection_module().new(%{
               app_ref: "app:demo:installation:acme:demo:tenant:dev",
               active_profile: "profile:monolith"
             })

    assert projection.active_profile == "profile:monolith"
  end
end
