defmodule Chassis.Secrets.Materializer.SopsTest do
  use ExUnit.Case, async: true

  alias Chassis.Keys.Manager
  alias Chassis.Secrets.{SecretLease, SecretRef}
  alias Chassis.Secrets.Materializer.Sops

  @pem """
  -----BEGIN PRIVATE KEY-----
  test-sops-private-key
  -----END PRIVATE KEY-----
  """

  defmodule FakeSopsBackend do
    def decrypt(path, opts) do
      send(
        Keyword.fetch!(opts, :test_pid),
        {:decrypt_called, path, Keyword.get(opts, :age_key_path)}
      )

      {:ok,
       %{
         "ssh_keys" => %{
           "vps_deploy_key" => Keyword.get(opts, :key_material, "fixture-key")
         },
         "metadata" => %{"created_at" => "2026-05-29T00:00:00Z"}
       }}
    end

    def encrypt(path, decoded, opts) do
      send(Keyword.fetch!(opts, :test_pid), {:encrypt_called, path, decoded})
      :ok
    end
  end

  test "materialize decrypts SOPS JSON through the injected boundary and never writes plaintext" do
    tmp_dir = unique_tmp_dir!()
    vault_path = Path.join(tmp_dir, "secrets.sops.json")
    File.write!(vault_path, "encrypted fixture")
    before_files = MapSet.new(File.ls!(tmp_dir))

    ref =
      SecretRef.new!(
        secret_ref: "secret:ssh:vps_deploy_key",
        tenant_ref: "tenant:nshkr",
        backend: :sops,
        path: vault_path,
        key: "ssh_keys.vps_deploy_key"
      )

    assert {:ok, lease} =
             Sops.materialize(ref,
               consumer_ref: "consumer:bootstrap",
               decryptor: FakeSopsBackend,
               age_key_path: "/tmp/age.txt",
               test_pid: self(),
               key_material: @pem
             )

    assert_receive {:decrypt_called, ^vault_path, "/tmp/age.txt"}
    assert %SecretLease{material: @pem, consumer_ref: "consumer:bootstrap"} = lease
    refute inspect(lease) =~ @pem
    assert MapSet.new(File.ls!(tmp_dir)) == before_files
  after
    if tmp_dir = Process.get(:tmp_dir), do: File.rm_rf(tmp_dir)
  end

  test "materialize returns key_not_found for absent nested keys instead of static fallback material" do
    ref =
      SecretRef.new!(
        secret_ref: "secret:ssh:missing",
        tenant_ref: "tenant:nshkr",
        backend: :sops,
        path: "/vault.json",
        key: "ssh_keys.missing"
      )

    assert {:error, {:key_not_found, "ssh_keys.missing"}} =
             Sops.materialize(ref,
               consumer_ref: "consumer:bootstrap",
               decryptor: FakeSopsBackend,
               test_pid: self()
             )
  end

  test "decrypt uses the real sops command shape and redacts failed command output" do
    parent = self()
    vault_path = "/tmp/secrets.sops.json"
    age_key_path = "/tmp/age-key.txt"
    decoded = %{"ssh_keys" => %{"vps_deploy_key" => @pem}}

    runner = fn "sops", ["--decrypt", "--output-type", "json", ^vault_path], opts ->
      send(parent, {:cmd_opts, opts})
      {Jason.encode!(decoded), 0}
    end

    assert {:ok, ^decoded} =
             Sops.decrypt(vault_path, age_key_path: age_key_path, cmd_runner: runner)

    assert_receive {:cmd_opts,
                    [env: [{"SOPS_AGE_KEY_FILE", ^age_key_path}], stderr_to_stdout: true]}

    failing_runner = fn "sops", ["--decrypt", "--output-type", "json", ^vault_path], _opts ->
      {"fatal: #{@pem}", 42}
    end

    assert {:error, {:sops_decrypt_failed, 42, message}} =
             Sops.decrypt(vault_path, age_key_path: age_key_path, cmd_runner: failing_runner)

    refute message =~ @pem
    refute message =~ "BEGIN PRIVATE KEY"
    assert message =~ "[REDACTED]"
  end

  test "key manager add/list/show/rotate mutates decrypted vault data and emits redacted receipts" do
    vault_path = "/tmp/secrets.sops.json"

    assert {:ok, added} =
             Manager.add("vps_deploy_key", @pem,
               vault_path: vault_path,
               crypto_backend: FakeSopsBackend,
               test_pid: self(),
               receipt_sink: fn receipt -> send(self(), {:receipt, receipt}) end,
               key_material: @pem
             )

    assert added.name == "vps_deploy_key"
    assert added.type == :ssh_key
    assert added.fingerprint =~ "SHA256:"
    refute inspect(added) =~ @pem

    assert_receive {:encrypt_called, ^vault_path, %{"ssh_keys" => %{"vps_deploy_key" => @pem}}}

    assert_receive {:receipt, %Chassis.Receipts.KeyRotationRecord{} = add_receipt}
    assert add_receipt.key_ref == "ssh_key:vps_deploy_key"
    assert add_receipt.fingerprint == added.fingerprint
    refute inspect(add_receipt) =~ @pem

    assert {:ok, listed} =
             Manager.list(
               vault_path: vault_path,
               crypto_backend: FakeSopsBackend,
               test_pid: self(),
               key_material: @pem
             )

    assert [%{name: "vps_deploy_key", type: :ssh_key, fingerprint: _}] = listed
    refute inspect(listed) =~ @pem

    assert {:ok, shown} =
             Manager.show("vps_deploy_key",
               vault_path: vault_path,
               crypto_backend: FakeSopsBackend,
               test_pid: self(),
               key_material: @pem
             )

    assert shown.name == "vps_deploy_key"
    refute Map.has_key?(shown, :material)
    refute inspect(shown) =~ @pem

    assert {:error, {:key_not_found, "missing"}} =
             Manager.show("missing",
               vault_path: vault_path,
               crypto_backend: FakeSopsBackend,
               test_pid: self(),
               key_material: @pem
             )

    assert {:ok, rotated} =
             Manager.rotate("vps_deploy_key", "new-private-key",
               vault_path: vault_path,
               crypto_backend: FakeSopsBackend,
               test_pid: self(),
               receipt_sink: fn receipt -> send(self(), {:receipt, receipt}) end,
               key_material: @pem
             )

    assert rotated.previous_version == "vps_deploy_key_v2"
    assert_receive {:encrypt_called, ^vault_path, rotated_doc}
    assert rotated_doc["ssh_keys"]["vps_deploy_key"] == "new-private-key"
    assert rotated_doc["ssh_keys"]["vps_deploy_key_v2"] == @pem
    assert_receive {:receipt, %Chassis.Receipts.KeyRotationRecord{} = rotate_receipt}
    assert rotate_receipt.key_ref == "ssh_key:vps_deploy_key"
    assert rotate_receipt.fingerprint == rotated.fingerprint
    refute inspect(rotate_receipt) =~ "new-private-key"
    refute inspect(rotated) =~ "new-private-key"
  end

  defp unique_tmp_dir! do
    path =
      Path.join(
        System.tmp_dir!(),
        "chassis-secret-sops-" <> Integer.to_string(System.unique_integer([:positive]))
      )

    File.mkdir_p!(path)
    Process.put(:tmp_dir, path)
    path
  end
end
