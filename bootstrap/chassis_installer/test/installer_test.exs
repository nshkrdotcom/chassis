defmodule Chassis.InstallerTest do
  @moduledoc """
  Phase 7 — `chassis_installer` release-bundle installer tests.

  Installer plans the install (release path resolution from environment
  config), validates the release tarball exists and matches the declared
  digest, and reports an `InstallationManifest`-shaped receipt.
  """
  use ExUnit.Case, async: true

  alias Chassis.Contracts.InstallationManifest
  alias Chassis.Installer

  setup do
    tmp = Path.join(System.tmp_dir!(), "chassis_installer_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    on_exit(fn -> File.rm_rf!(tmp) end)

    tarball = Path.join(tmp, "demo-0.1.0.tar.gz")
    File.write!(tarball, "FAKE-RELEASE-CONTENT")

    digest = :crypto.hash(:sha256, File.read!(tarball)) |> Base.encode16(case: :lower)

    %{tmp: tmp, tarball: tarball, digest: digest}
  end

  describe "Installer.plan/2" do
    test "resolves release_path from environment install_paths and stamps installation_ref", %{tarball: tarball} do
      env = %{install_paths: %{release: "/opt/nshkr/releases"}, env_config_ref: "linode"}
      manifest = %{installation_ref: "install:demo", release_tarball_path: tarball}

      assert {:ok, plan} = Installer.plan(manifest, env)
      assert plan.installation_ref == "install:demo"
      assert plan.release_path == "/opt/nshkr/releases"
      assert plan.release_tarball_path == tarball
    end

    test "errors when release_tarball_path is missing", %{} do
      env = %{install_paths: %{release: "/tmp"}}
      assert {:error, :missing_tarball_path} = Installer.plan(%{installation_ref: "i:1"}, env)
    end

    test "errors when env has no install_paths.release", %{tarball: tarball} do
      env = %{install_paths: %{}}
      assert {:error, :missing_release_path} =
               Installer.plan(%{installation_ref: "i:1", release_tarball_path: tarball}, env)
    end
  end

  describe "Installer.verify_digest/2" do
    test "passes when computed sha256 matches the expected", %{tarball: tarball, digest: digest} do
      assert :ok = Installer.verify_digest(tarball, digest)
    end

    test "fails with structured error on digest mismatch", %{tarball: tarball} do
      assert {:error, {:digest_mismatch, _expected, _actual}} =
               Installer.verify_digest(tarball, "deadbeef")
    end

    test "fails with :enoent on missing file" do
      assert {:error, :enoent} = Installer.verify_digest("/no/such/file", "x")
    end
  end

  describe "Installer.install/2 — happy path" do
    test "returns an InstallationManifest with computed digest", %{tarball: tarball, digest: digest} do
      env = %{install_paths: %{release: "/opt/nshkr/releases"}}

      manifest = %{
        installation_ref: "install:demo",
        release_tarball_path: tarball,
        expected_digest: digest
      }

      assert {:ok, %InstallationManifest{} = result} = Installer.install(manifest, env)
      assert result.installation_ref == "install:demo"
      assert result.release_tarball_path == tarball
      assert result.paths[:release] == "/opt/nshkr/releases"
    end

    test "refuses to install when digest does not match", %{tarball: tarball} do
      env = %{install_paths: %{release: "/opt/nshkr/releases"}}

      manifest = %{
        installation_ref: "install:demo",
        release_tarball_path: tarball,
        expected_digest: "deadbeef"
      }

      assert {:error, {:digest_mismatch, _, _}} = Installer.install(manifest, env)
    end
  end

  describe "Installer.systemd_unit/1" do
    test "generates a unit with EnvironmentFile + Restart=on-failure" do
      unit =
        Installer.systemd_unit(%{
          service_ref: "service:demo",
          command: "/opt/nshkr/releases/demo/bin/demo start"
        })

      assert unit =~ "EnvironmentFile=/opt/nshkr/secrets/service.env"
      assert unit =~ "Restart=on-failure"
      assert unit =~ "ExecStart=/opt/nshkr/releases/demo/bin/demo start"
    end
  end
end
