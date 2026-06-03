defmodule Chassis.Secrets.SecretRefsTest do
  use ExUnit.Case, async: true

  alias Chassis.Secrets.{LeaseSupervisor, MaterializationRecord, SecretLease, SecretRef}

  @pem """
  -----BEGIN PRIVATE KEY-----
  test-private-key-material
  -----END PRIVATE KEY-----
  """

  test "SecretRef validates required fields and serializes only descriptor data" do
    assert {:ok, ref} =
             SecretRef.new(
               secret_ref: "secret:ssh:vps_deploy_key",
               tenant_ref: "tenant:nshkr",
               backend: :sops,
               path: "/home/operator/.config/chassis/secrets.sops.json",
               key: "ssh_keys.vps_deploy_key"
             )

    assert %SecretRef{
             secret_ref: "secret:ssh:vps_deploy_key",
             tenant_ref: "tenant:nshkr",
             backend: :sops,
             path: "/home/operator/.config/chassis/secrets.sops.json",
             key: "ssh_keys.vps_deploy_key",
             redaction_policy_ref: "redaction:secret-standard"
           } = ref

    encoded = Jason.encode!(ref)
    assert encoded =~ "secret:ssh:vps_deploy_key"
    refute encoded =~ "material"

    assert {:error, {:invalid_backend, :aws}} =
             SecretRef.new(
               secret_ref: "secret:bad",
               tenant_ref: "tenant:nshkr",
               backend: :aws,
               path: "/vault.json",
               key: "ssh_keys.bad"
             )

    assert {:error, {:missing_required, :tenant_ref}} =
             SecretRef.new(
               secret_ref: "secret:missing_tenant",
               backend: :env,
               key: "CHASSIS_SECRET"
             )
  end

  test "SecretLease carries material only in memory and redacts inspect and JSON output" do
    ref =
      SecretRef.new!(
        secret_ref: "secret:ssh:vps_deploy_key",
        tenant_ref: "tenant:nshkr",
        backend: :sops,
        path: "/vault.json",
        key: "ssh_keys.vps_deploy_key"
      )

    started_at = DateTime.utc_now()

    assert {:ok, lease} =
             SecretLease.new(ref, @pem, consumer_ref: "consumer:bootstrap", ttl_seconds: 999)

    assert %SecretLease{
             lease_ref: "lease:" <> _,
             secret_ref: "secret:ssh:vps_deploy_key",
             material: @pem,
             consumer_ref: "consumer:bootstrap"
           } = lease

    assert DateTime.diff(lease.expires_at, started_at, :second) in 299..300

    inspected = inspect(lease)
    assert inspected =~ "<redacted>"
    refute inspected =~ @pem
    refute inspected =~ "BEGIN PRIVATE KEY"

    encoded = Jason.encode!(lease)
    assert encoded =~ lease.lease_ref
    assert encoded =~ lease.secret_ref
    refute encoded =~ @pem
    refute encoded =~ "material"
  end

  test "MaterializationRecord hashes target paths and excludes raw secret material and paths" do
    ref =
      SecretRef.new!(
        secret_ref: "secret:ssh:vps_deploy_key",
        tenant_ref: "tenant:nshkr",
        backend: :sops,
        path: "/vault.json",
        key: "ssh_keys.vps_deploy_key"
      )

    lease = SecretLease.new!(ref, @pem, consumer_ref: "consumer:bootstrap")
    target_path = "/tmp/chassis_ssh/private_key"

    assert {:ok, record} =
             MaterializationRecord.new(ref, lease,
               target_path: target_path,
               status: :ok
             )

    assert record.secret_ref == ref.secret_ref
    assert record.lease_ref == lease.lease_ref
    assert record.backend == :sops
    assert record.consumer_ref == "consumer:bootstrap"

    assert record.target_path_hash ==
             :crypto.hash(:sha256, target_path) |> Base.encode16(case: :lower)

    assert record.status == :ok

    inspected = inspect(record)
    refute inspected =~ target_path
    refute inspected =~ @pem
  end

  test "LeaseSupervisor authorizes consumers, expires leases, and runs cleanup callbacks" do
    ref =
      SecretRef.new!(
        secret_ref: "secret:ssh:vps_deploy_key",
        tenant_ref: "tenant:nshkr",
        backend: :sops,
        path: "/vault.json",
        key: "ssh_keys.vps_deploy_key"
      )

    lease =
      ref
      |> SecretLease.new!(@pem, consumer_ref: "consumer:bootstrap")
      |> Map.put(:expires_at, DateTime.add(DateTime.utc_now(), 80, :millisecond))

    test_pid = self()
    supervisor = start_supervised!({LeaseSupervisor, name: nil})

    assert {:ok, lease_pid} =
             LeaseSupervisor.register_lease(supervisor, lease,
               cleanup_callbacks: [
                 fn expired_lease -> send(test_pid, {:cleaned, expired_lease.lease_ref}) end
               ]
             )

    assert Process.alive?(lease_pid)

    assert {:ok, @pem} =
             LeaseSupervisor.get_material(supervisor, lease.lease_ref, "consumer:bootstrap")

    assert {:error, :unauthorized_consumer} =
             LeaseSupervisor.get_material(supervisor, lease.lease_ref, "consumer:other")

    assert_receive {:cleaned, "lease:" <> _}, 1_000

    assert {:error, :not_found} =
             LeaseSupervisor.get_material(supervisor, lease.lease_ref, "consumer:bootstrap")

    refute Process.alive?(lease_pid)
  end
end
