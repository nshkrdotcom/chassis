defmodule Chassis.CLI.CommandDispatchTest do
  use ExUnit.Case, async: false

  alias Chassis.CLI
  alias Chassis.Receipts.{DeploymentRecord, Store}

  @phase20_commands %{
    "stack.deploy" => [
      "stack.deploy",
      "extravaganza",
      "--profile",
      "profile:monolith",
      "--env",
      "dev"
    ],
    "stack.status" => ["stack.status"],
    "stack.rollback" => ["stack.rollback", "app:missing"],
    "stack.diff" => [
      "stack.diff",
      "--from",
      "profile:monolith",
      "--to",
      "profile:ternary-split-3"
    ],
    "host.inventory" => ["host.inventory"],
    "host.inspect" => ["host.inspect", "host:local"],
    "node.doctor" => ["node.doctor"],
    "node.bootstrap" => ["node.bootstrap", "host:local"],
    "app.list" => ["app.list"],
    "app.deploy" => [
      "app.deploy",
      "extravaganza",
      "--profile",
      "profile:monolith",
      "--env",
      "dev"
    ],
    "app.rollback" => ["app.rollback", "app:missing"],
    "keys.add" => ["keys.add", "deploy_key"],
    "keys.list" => ["keys.list"],
    "keys.show" => ["keys.show", "deploy_key"],
    "keys.rotate" => ["keys.rotate", "deploy_key"],
    "env.list" => ["env.list"],
    "env.show" => ["env.show", "local_ubuntu_24_04"],
    "proof.run" => ["proof.run"]
  }

  setup do
    reset_runtime()
    on_exit(&reset_runtime/0)
    :ok
  end

  test "all Phase 20 commands route to active command modules instead of router not_implemented" do
    for {command, argv} <- @phase20_commands do
      {_code, payload} = CLI.dispatch(argv)

      if payload[:error] == "not_implemented" do
        assert payload[:routed?],
               "#{command} may only return not_implemented from an active command module"
      end
    end
  end

  test "stack.deploy --no-mezzanine dispatches through StackManager.Transaction.run/1 with side effects" do
    argv = [
      "stack.deploy",
      "extravaganza",
      "--profile",
      "profile:monolith",
      "--env",
      "dev",
      "--tenant",
      "tenant:dev",
      "--installation",
      "installation:dev",
      "--idempotency-key",
      "cli-direct-deploy",
      "--no-mezzanine"
    ]

    assert {0, %{status: :active, receipt_ref: receipt_ref, command: "stack.deploy"} = first} =
             CLI.dispatch(argv)

    assert {:ok, [entry]} = Chassis.AppRegistry.list(Chassis.CLI.Runtime.registry(), [])
    assert entry.app_atom == :extravaganza
    assert entry.tenant_ref == "tenant:dev"
    assert entry.last_deployment_receipt_ref == receipt_ref

    assert [%DeploymentRecord{receipt_ref: ^receipt_ref, tenant_ref: "tenant:dev"}] =
             Store.Memory.list(Chassis.CLI.Runtime.receipts_store(), kind: DeploymentRecord)

    assert {0, %{idempotent?: true, receipt_ref: ^receipt_ref}} = CLI.dispatch(argv)
    refute first[:status] == "active-static"
  end

  test "stack.deploy defaults through the Mezzanine bridge and still writes deployment receipts" do
    assert {0, payload} =
             CLI.dispatch([
               "stack.deploy",
               "extravaganza",
               "--profile",
               "profile:monolith",
               "--env",
               "dev",
               "--tenant",
               "tenant:dev",
               "--installation",
               "installation:dev",
               "--idempotency-key",
               "cli-mezzanine-deploy"
             ])

    assert payload.via == :mezzanine
    assert payload.status == :active
    assert payload.deployment_receipt_ref =~ "receipt:deployment"

    assert [%DeploymentRecord{receipt_ref: receipt_ref}] =
             Store.Memory.list(Chassis.CLI.Runtime.receipts_store(), kind: DeploymentRecord)

    assert receipt_ref == payload.deployment_receipt_ref
  end

  test "host.inventory reads a real hosts file and filters by tenant" do
    path = tmp_path("hosts.json")

    File.write!(path, """
    [
      {"host_ref":"host:acme","provider":"hetzner","region":"fsn1","hostname":"appkit@fsn1","resources":{"cpu_cores":4,"ram_gb":8,"gpus":0},"tenant_refs":["tenant:acme"]},
      {"host_ref":"host:other","provider":"linode","region":"newark","hostname":"appkit@newark","resources":{"cpu_cores":4,"ram_gb":8,"gpus":0},"tenant_refs":["tenant:other"]}
    ]
    """)

    assert {0, %{hosts: [%{host_ref: "host:acme"}], count: 1}} =
             CLI.dispatch(["host.inventory", "--hosts", path, "--tenant", "tenant:acme"])

    assert {1, %{error: "command_failed", reason: reason}} =
             CLI.dispatch(["host.inventory", "--hosts", tmp_path("missing.json")])

    assert reason =~ ":enoent"
  end

  test "keys commands use the key manager and never echo raw key material" do
    vault_path = tmp_path("vault.json")
    material_path = tmp_path("id_ed25519")
    rotated_path = tmp_path("id_ed25519_rotated")
    File.write!(material_path, "PRIVATE KEY BYTES phase20 original")
    File.write!(rotated_path, "PRIVATE KEY BYTES phase20 rotated")

    assert {0, added} =
             CLI.dispatch([
               "keys.add",
               "deploy_key",
               "--material-file",
               material_path,
               "--vault-path",
               vault_path,
               "--plaintext-vault"
             ])

    assert added.event_type == :added
    refute inspect(added) =~ "PRIVATE KEY BYTES"

    assert {0, %{keys: [%{name: "deploy_key", fingerprint: fingerprint}]}} =
             CLI.dispatch(["keys.list", "--vault-path", vault_path, "--plaintext-vault"])

    assert fingerprint == added.fingerprint

    assert {0, shown} =
             CLI.dispatch([
               "keys.show",
               "deploy_key",
               "--vault-path",
               vault_path,
               "--plaintext-vault"
             ])

    assert shown.fingerprint == added.fingerprint
    refute inspect(shown) =~ "PRIVATE KEY BYTES"

    assert {0, rotated} =
             CLI.dispatch([
               "keys.rotate",
               "deploy_key",
               "--material-file",
               rotated_path,
               "--vault-path",
               vault_path,
               "--plaintext-vault"
             ])

    assert rotated.event_type == :rotated
    assert rotated.previous_version == "deploy_key_v2"
    refute inspect(rotated) =~ "PRIVATE KEY BYTES"
  end

  test "env commands read the embedded environment catalog" do
    assert {0, %{environments: envs, count: count}} = CLI.dispatch(["env.list"])
    assert count >= 4
    assert Enum.any?(envs, &(&1.env_config_ref == "local_ubuntu_24_04"))

    assert {0, %{environment: env}} = CLI.dispatch(["env.show", "local_ubuntu_24_04"])
    assert env.env_config_ref == "local_ubuntu_24_04"

    assert {1, %{error: "command_failed", reason: ":unknown_environment"}} =
             CLI.dispatch(["env.show", "nope"])
  end

  test "app.list and stack.status return table payloads rendered by Bunt for human output" do
    {0, _payload} =
      CLI.dispatch([
        "stack.deploy",
        "extravaganza",
        "--profile",
        "profile:monolith",
        "--env",
        "dev",
        "--tenant",
        "tenant:dev",
        "--installation",
        "installation:dev",
        "--idempotency-key",
        "cli-table-deploy",
        "--no-mezzanine"
      ])

    assert {0, app_payload} = CLI.dispatch(["app.list"])
    assert app_payload.format == :table
    assert [%{app_atom: :extravaganza}] = app_payload.rows
    assert CLI.Encoding.encode(app_payload, json?: false) =~ "\e["

    assert {0, status_payload} = CLI.dispatch(["stack.status"])
    assert status_payload.format == :table
    assert [%{status: :active}] = status_payload.rows
    assert CLI.Encoding.encode(status_payload, json?: false) =~ "\e["
  end

  defp reset_runtime do
    if Code.ensure_loaded?(Chassis.CLI.Runtime) and
         function_exported?(Chassis.CLI.Runtime, :reset!, 0) do
      Chassis.CLI.Runtime.reset!()
    end
  end

  defp tmp_path(name) do
    root =
      Path.join(System.tmp_dir!(), "chassis_cli_phase20_#{System.unique_integer([:positive])}")

    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    Path.join(root, name)
  end
end
