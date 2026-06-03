defmodule Chassis.AppRegistryTest do
  use ExUnit.Case, async: true

  alias Chassis.AppRegistry
  alias Chassis.AppRegistry.Backend
  alias Chassis.AppRegistry.Entry
  alias Chassis.Releases.Bundle

  test "Entry requires the documented deployment fields and rejects bad enums" do
    attrs = entry_attrs("app:one")

    assert {:ok, %Entry{} = entry} = Entry.new(attrs)
    assert Entry.fields() |> length() == 14
    assert entry.app_ref == "app:one"
    assert entry.app_atom == :extravaganza
    assert entry.environment == :dev
    assert entry.status == :active
    assert %DateTime{} = entry.deployed_at
    assert %DateTime{} = entry.updated_at

    assert {:error, {:missing_required, :tenant_ref}} =
             attrs |> Map.delete(:tenant_ref) |> Entry.new()

    assert {:error, {:invalid_environment, :stage}} = Entry.new(%{attrs | environment: :stage})
    assert {:error, {:invalid_status, :unknown}} = Entry.new(%{attrs | status: :unknown})
  end

  test "Registry is a GenServer with ETS backend, duplicate conflict resolution, and active profile lookup" do
    registry = start_supervised!({AppRegistry, name: nil})

    assert {:ok, first} = AppRegistry.register(registry, entry!("app:dupe", "receipt:one"))
    assert {:ok, ^first} = AppRegistry.lookup(registry, "app:dupe")
    assert {:ok, "profile:monolith"} = AppRegistry.active_profile(registry, "app:dupe")

    replacement =
      entry!("app:dupe", "receipt:two",
        active_profile: "profile:ternary-split-3",
        release_version: "v2"
      )

    assert {:ok, replaced} = AppRegistry.register(registry, replacement)
    assert replaced.last_deployment_receipt_ref == "receipt:two"
    assert replaced.rollback_target_ref == "receipt:one"
    assert replaced.active_profile == "profile:ternary-split-3"
    assert {:ok, [^replaced]} = AppRegistry.list(registry, app_atom: :extravaganza)

    assert :ok =
             AppRegistry.update_status(registry, "app:dupe", :rolling_back,
               rollback_target_ref: "receipt:one"
             )

    assert {:ok, rolling} = AppRegistry.lookup(registry, "app:dupe")
    assert rolling.status == :rolling_back
    assert rolling.rollback_target_ref == "receipt:one"
  end

  test "Registry supports concurrent registrations without losing entries" do
    registry = start_supervised!({AppRegistry, name: nil})

    1..40
    |> Task.async_stream(fn idx ->
      AppRegistry.register(registry, entry!("app:#{idx}", "receipt:#{idx}"))
    end)
    |> Enum.each(fn {:ok, {:ok, %Entry{}}} -> :ok end)

    assert {:ok, entries} = AppRegistry.list(registry, [])
    assert length(entries) == 40
    assert {:ok, "profile:monolith"} = AppRegistry.active_profile(registry, "app:17")
  end

  test "AshPostgres backend is an explicit future adapter" do
    entry = entry!("app:pg", "receipt:pg")

    assert {:error, {:not_implemented, Backend.AshPostgres}} = Backend.AshPostgres.init([])
    assert {:error, {:not_implemented, Backend.AshPostgres}} = Backend.AshPostgres.put(nil, entry)

    assert {:error, {:not_implemented, Backend.AshPostgres}} =
             Backend.AshPostgres.get(nil, "app:pg")

    assert {:error, {:not_implemented, Backend.AshPostgres}} = Backend.AshPostgres.list(nil, [])

    assert {:error, {:not_implemented, Backend.AshPostgres}} =
             Backend.AshPostgres.delete(nil, "app:pg")
  end

  test "Bundle materializer reads bytes from disk and validates sha256" do
    path =
      Path.join(System.tmp_dir!(), "chassis-release-#{System.unique_integer([:positive])}.tar")

    bytes = "release tarball bytes"
    File.write!(path, bytes)

    on_exit(fn -> File.rm(path) end)

    digest = Bundle.sha256(bytes)
    assert {:ok, bundle} = Bundle.materialize(path, expected_sha256: digest)
    assert bundle.path == path
    assert bundle.bytes == bytes
    assert bundle.sha256 == digest
    assert bundle.size_bytes == byte_size(bytes)

    assert {:error, {:sha256_mismatch, "sha256:bad", ^digest}} =
             Bundle.materialize(path, expected_sha256: "sha256:bad")
  end

  defp entry!(app_ref, receipt_ref, overrides \\ []) do
    entry_attrs(app_ref)
    |> Map.merge(Map.new(overrides))
    |> Map.put(:last_deployment_receipt_ref, receipt_ref)
    |> Entry.new!()
  end

  defp entry_attrs(app_ref) do
    %{
      app_ref: app_ref,
      app_atom: :extravaganza,
      installation_ref: "installation:default",
      tenant_ref: "tenant:dev",
      active_profile: "profile:monolith",
      environment: :dev,
      git_sha: "abc123",
      release_version: "v1",
      node_mesh: [:node@host],
      status: :active,
      last_deployment_receipt_ref: "receipt:deployment:one"
    }
  end
end
