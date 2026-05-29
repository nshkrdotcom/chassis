defmodule Chassis.Package.ArtifactFs.SmokeTest do
  use ExUnit.Case, async: true

  test "package marker is compiled" do
    assert Chassis.Package.ArtifactFs.package_ref() == "chassis_artifact_fs"
    assert Chassis.Package.ArtifactFs.implemented?()
  end
end
