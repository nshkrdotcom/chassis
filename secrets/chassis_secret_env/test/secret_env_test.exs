defmodule Chassis.Secrets.Materializer.EnvTest do
  use ExUnit.Case, async: false

  alias Chassis.Secrets.{SecretLease, SecretRef}
  alias Chassis.Secrets.Materializer.Env

  @env_var "CHASSIS_SECRET_ENV_TEST_KEY"
  @material "env-secret-material"

  setup do
    previous = System.get_env(@env_var)
    System.delete_env(@env_var)

    on_exit(fn ->
      if previous, do: System.put_env(@env_var, previous), else: System.delete_env(@env_var)
    end)

    :ok
  end

  test "materialize reads the configured env var into a redacted SecretLease" do
    System.put_env(@env_var, @material)

    ref =
      SecretRef.new!(
        secret_ref: "secret:env:test",
        tenant_ref: "tenant:nshkr",
        backend: :env,
        key: @env_var
      )

    assert {:ok, lease} = Env.materialize(ref, consumer_ref: "consumer:test", ttl_seconds: 45)
    assert %SecretLease{secret_ref: "secret:env:test", material: @material} = lease
    assert DateTime.diff(lease.expires_at, DateTime.utc_now(), :second) in 44..45
    refute inspect(lease) =~ @material
    assert :ok = Env.revoke(lease)
  end

  test "materialize fails when the env var is unset and never fabricates material" do
    ref =
      SecretRef.new!(
        secret_ref: "secret:env:missing",
        tenant_ref: "tenant:nshkr",
        backend: :env,
        key: @env_var
      )

    assert {:error, {:env_var_unset, @env_var}} =
             Env.materialize(ref, consumer_ref: "consumer:test")
  end

  test "materialize rejects unsupported backends and missing consumers" do
    sops_ref =
      SecretRef.new!(
        secret_ref: "secret:sops:test",
        tenant_ref: "tenant:nshkr",
        backend: :sops,
        path: "/vault.json",
        key: "ssh_keys.test"
      )

    assert {:error, {:unsupported_backend, :sops}} =
             Env.materialize(sops_ref, consumer_ref: "consumer:test")

    env_ref =
      SecretRef.new!(
        secret_ref: "secret:env:test",
        tenant_ref: "tenant:nshkr",
        backend: :env,
        key: @env_var
      )

    assert {:error, {:missing_option, :consumer_ref}} = Env.materialize(env_ref, [])
  end
end
