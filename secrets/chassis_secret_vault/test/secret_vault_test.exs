defmodule Chassis.Secrets.Materializer.VaultTest do
  use ExUnit.Case, async: true

  alias Chassis.Secrets.SecretRef
  alias Chassis.Secrets.Materializer.Vault

  test "materialize returns the canonical explicit future-adapter error" do
    ref =
      SecretRef.new!(
        secret_ref: "secret:vault:future",
        tenant_ref: "tenant:nshkr",
        backend: :vault,
        path: "kv/data/chassis",
        key: "ssh_keys.vps_deploy_key"
      )

    assert {:error, {:not_implemented, Vault}} =
             Vault.materialize(ref, consumer_ref: "consumer:test")
  end

  test "revoke is a no-op for an unmaterialized future adapter lease" do
    assert :ok = Vault.revoke(%{})
  end
end
