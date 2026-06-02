defmodule Chassis.Installer do
  @moduledoc """
  Target-host release-bundle installer.

  The installer:

  1. `plan/2` resolves the install path from the environment's
     `install_paths.release` and validates the tarball path is supplied.
  2. `verify_digest/2` computes sha256 over the tarball bytes and compares
     to the expected digest.
  3. `install/2` plans + verifies + returns a
     `Chassis.Contracts.InstallationManifest`.
  4. `systemd_unit/1` renders the standard chassis service unit with
     `EnvironmentFile=/opt/nshkr/secrets/service.env` and `Restart=on-failure`.

  Actual byte transfer to the remote host is performed by
  `Chassis.Provisioning.SSHBootstrap.upload_release/3` and is exercised by
  the Phase 7 bootstrap test suite. The Installer module owns the planning
  and digest-verification surfaces and is dependency-free of any transport.
  """

  alias Chassis.Contracts.InstallationManifest

  @type plan :: %{
          installation_ref: String.t(),
          release_path: String.t(),
          release_tarball_path: String.t()
        }

  @spec plan(map(), map()) :: {:ok, plan()} | {:error, term()}
  def plan(manifest, env) do
    with {:ok, tarball} <- fetch(manifest, :release_tarball_path, :missing_tarball_path),
         {:ok, release_path} <- fetch_release_path(env) do
      {:ok,
       %{
         installation_ref: Map.get(manifest, :installation_ref),
         release_path: release_path,
         release_tarball_path: tarball
       }}
    end
  end

  @spec verify_digest(Path.t(), String.t()) ::
          :ok | {:error, {:digest_mismatch, String.t(), String.t()} | :enoent | term()}
  def verify_digest(path, expected_hex) do
    case File.read(path) do
      {:ok, bytes} ->
        actual = :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)
        if actual == String.downcase(expected_hex), do: :ok, else: {:error, {:digest_mismatch, expected_hex, actual}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec install(map(), map()) :: {:ok, InstallationManifest.t()} | {:error, term()}
  def install(manifest, env) do
    with {:ok, plan} <- plan(manifest, env),
         :ok <- maybe_verify(plan, Map.get(manifest, :expected_digest)) do
      {:ok,
       %InstallationManifest{
         installation_ref: plan.installation_ref,
         release_tarball_path: plan.release_tarball_path,
         systemd_unit_name: "chassis-#{plan.installation_ref}.service",
         paths: %{release: plan.release_path},
         deps: Map.get(manifest, :deps, []),
         os_packages: Map.get(manifest, :os_packages, [])
       }}
    end
  end

  @spec systemd_unit(map()) :: String.t()
  def systemd_unit(service) do
    exec = Map.get(service, :command, "/bin/true")

    """
    [Service]
    EnvironmentFile=/opt/nshkr/secrets/service.env
    Restart=on-failure
    ExecStart=#{exec}
    """
  end

  defp fetch(map, key, missing) do
    case Map.get(map, key) do
      nil -> {:error, missing}
      "" -> {:error, missing}
      v -> {:ok, v}
    end
  end

  defp fetch_release_path(env) do
    case get_in(env, [:install_paths, :release]) || get_in(env, [Access.key(:install_paths), :release]) do
      nil -> {:error, :missing_release_path}
      path -> {:ok, path}
    end
  end

  defp maybe_verify(_plan, nil), do: :ok
  defp maybe_verify(plan, digest), do: verify_digest(plan.release_tarball_path, digest)
end
