defmodule Chassis.ReceiptsTest do
  @moduledoc """
  Phase 2 — `chassis_receipts` behavioral tests.

  Covers the receipt store behaviour, the in-memory backend (ETS-backed,
  GenServer-supervised), the JSONL appender, and the per-record types with
  their redaction guarantees.

  The AshPostgres backend is DEFERRED until a real database is wired
  (Phases 11/18); the behaviour is exercised by the Memory backend, which
  must implement every callback identically and pass the same contract
  tests.
  """
  use ExUnit.Case, async: false

  alias Chassis.Receipts
  alias Chassis.Receipts.Store

  alias Chassis.Receipts.{
    AITraceReceipt,
    BoundaryRecord,
    DeploymentRecord,
    KeyRotationRecord,
    MaterializationRecord,
    ProvisioningRecord,
    RollbackRecord,
    TenantAwareDeploymentReceipt
  }

  setup do
    {:ok, pid} = Store.Memory.start_link(name: nil)
    on_exit(fn -> if Process.alive?(pid), do: Process.exit(pid, :kill) end)
    %{store: pid}
  end

  describe "Store behaviour contract" do
    test "Store behaviour defines the documented callbacks" do
      callbacks = Store.behaviour_info(:callbacks) |> MapSet.new()

      assert MapSet.subset?(
               MapSet.new([{:put, 2}, {:get, 2}, {:list, 2}, {:delete, 2}]),
               callbacks
             )
    end
  end

  describe "Memory backend put/get round-trip" do
    test "stores and retrieves a DeploymentRecord identical minus computed fields", %{store: pid} do
      record = %DeploymentRecord{
        receipt_ref: Receipts.new_ref("receipt:deployment"),
        app_ref: "extravaganza",
        profile_ref: "profile:monolith",
        env: :dev,
        status: :active,
        authority_ref: "authority:decision:local",
        tenant_ref: "tenant:dev",
        secret_refs: ["secret:ssh_key:test"]
      }

      assert {:ok, stored} = Store.Memory.put(pid, record)
      assert stored.receipt_ref == record.receipt_ref
      # written_at is computed
      assert %DateTime{} = stored.written_at

      assert {:ok, fetched} = Store.Memory.get(pid, record.receipt_ref)
      assert fetched.app_ref == record.app_ref
      assert fetched.status == :active
    end

    test "get returns {:error, :not_found} for an unknown ref", %{store: pid} do
      assert {:error, :not_found} = Store.Memory.get(pid, "receipt:deployment:does-not-exist")
    end

    test "list filters by kind", %{store: pid} do
      {:ok, _} =
        Store.Memory.put(pid, %DeploymentRecord{
          receipt_ref: "receipt:deployment:1",
          app_ref: "a",
          profile_ref: "p",
          env: :dev,
          status: :active
        })

      {:ok, _} =
        Store.Memory.put(pid, %RollbackRecord{
          receipt_ref: "receipt:rollback:1",
          deployment_receipt_ref: "receipt:deployment:1",
          trigger: :operator,
          status: :rolled_back
        })

      deployments = Store.Memory.list(pid, kind: DeploymentRecord)
      rollbacks = Store.Memory.list(pid, kind: RollbackRecord)

      assert length(deployments) == 1
      assert length(rollbacks) == 1
      assert hd(deployments).receipt_ref == "receipt:deployment:1"
      assert hd(rollbacks).trigger == :operator
    end

    test "put rejects malformed records", %{store: pid} do
      assert {:error, {:invalid_record, _}} = Store.Memory.put(pid, %{not_a_struct: true})
    end
  end

  describe "Memory backend lifecycle" do
    test "store survives a put then re-read across many records", %{store: pid} do
      refs =
        for i <- 1..50 do
          ref = "receipt:deployment:#{i}"

          {:ok, _} =
            Store.Memory.put(pid, %DeploymentRecord{
              receipt_ref: ref,
              app_ref: "a",
              profile_ref: "p",
              env: :dev,
              status: :active
            })

          ref
        end

      for ref <- refs do
        assert {:ok, %DeploymentRecord{}} = Store.Memory.get(pid, ref)
      end

      assert length(Store.Memory.list(pid, kind: DeploymentRecord)) == 50
    end

    test "delete removes the record and is idempotent", %{store: pid} do
      ref = "receipt:deployment:to-delete"

      {:ok, _} =
        Store.Memory.put(pid, %DeploymentRecord{
          receipt_ref: ref,
          app_ref: "a",
          profile_ref: "p",
          env: :dev,
          status: :active
        })

      assert :ok = Store.Memory.delete(pid, ref)
      assert {:error, :not_found} = Store.Memory.get(pid, ref)
      assert :ok = Store.Memory.delete(pid, ref)
    end
  end

  describe "JSONL appender" do
    test "appends one record per line to the configured jsonl path", %{store: _store_setup} do
      tmp =
        Path.join(
          System.tmp_dir!(),
          "chassis_receipts_#{System.unique_integer([:positive])}.jsonl"
        )

      on_exit(fn -> File.rm(tmp) end)

      {:ok, pid2} = Store.Memory.start_link(name: nil, jsonl_path: tmp)
      on_exit(fn -> if Process.alive?(pid2), do: Process.exit(pid2, :kill) end)

      {:ok, _} =
        Store.Memory.put(pid2, %DeploymentRecord{
          receipt_ref: "receipt:deployment:jsonl-1",
          app_ref: "a",
          profile_ref: "p",
          env: :dev,
          status: :active
        })

      {:ok, _} =
        Store.Memory.put(pid2, %DeploymentRecord{
          receipt_ref: "receipt:deployment:jsonl-2",
          app_ref: "b",
          profile_ref: "p",
          env: :dev,
          status: :active
        })

      contents = File.read!(tmp)
      lines = String.split(contents, "\n", trim: true)
      assert length(lines) == 2
      assert hd(lines) =~ "receipt:deployment:jsonl-1"
      assert Enum.at(lines, 1) =~ "receipt:deployment:jsonl-2"

      # each line is canonical JSON parseable
      for line <- lines, do: assert({:ok, _} = Jason.decode(line))
    end
  end

  describe "Receipt redaction" do
    test "DeploymentRecord with secret_refs never leaks raw secret material to JSONL", %{} do
      tmp =
        Path.join(
          System.tmp_dir!(),
          "chassis_receipts_redact_#{System.unique_integer([:positive])}.jsonl"
        )

      on_exit(fn -> File.rm(tmp) end)

      {:ok, pid} = Store.Memory.start_link(name: nil, jsonl_path: tmp)
      on_exit(fn -> if Process.alive?(pid), do: Process.exit(pid, :kill) end)

      raw_key = "BEGIN RSA PRIVATE KEY: " <> Base.encode16(:crypto.strong_rand_bytes(32))

      record = %DeploymentRecord{
        receipt_ref: "receipt:deployment:redact",
        app_ref: "a",
        profile_ref: "p",
        env: :dev,
        status: :active,
        secret_refs: ["secret:ssh_key:fixture"],
        # we should NEVER write this to the jsonl, even by accident
        material: raw_key,
        password: raw_key,
        labels: %{"webhook_secret" => raw_key}
      }

      {:ok, _} = Store.Memory.put(pid, record)
      contents = File.read!(tmp)

      refute contents =~ raw_key
      refute contents =~ "BEGIN RSA PRIVATE KEY"
      assert contents =~ "[REDACTED]"
    end

    test "DeploymentRecord Inspect implementation masks material/password/secret-flavored fields" do
      record = %DeploymentRecord{
        receipt_ref: "receipt:1",
        app_ref: "a",
        profile_ref: "p",
        env: :dev,
        status: :active,
        material: "super-secret-bytes",
        password: "super-password"
      }

      str = inspect(record)
      refute str =~ "super-secret-bytes"
      refute str =~ "super-password"
      assert str =~ "[REDACTED]"
    end
  end

  describe "per-record types" do
    test "RollbackRecord trigger enum is enforced by the put pipeline", %{store: pid} do
      bad = %RollbackRecord{
        receipt_ref: "rb:1",
        deployment_receipt_ref: "d:1",
        trigger: :unknown_trigger,
        status: :rolled_back
      }

      assert {:error, {:invalid_record, _}} = Store.Memory.put(pid, bad)

      ok = %RollbackRecord{
        receipt_ref: "rb:2",
        deployment_receipt_ref: "d:1",
        trigger: :metabolic_self_healing,
        status: :rolled_back
      }

      assert {:ok, _} = Store.Memory.put(pid, ok)
    end

    test "ProvisioningRecord captures host, attempt, and step list" do
      r = %ProvisioningRecord{
        receipt_ref: "receipt:provisioning:1",
        host_ref: "host:local",
        attempt: 1,
        steps: [:fence_acquire, :ssh_connect, :install_packages],
        status: :ok
      }

      assert r.attempt == 1
      assert :ssh_connect in r.steps
    end

    test "KeyRotationRecord and MaterializationRecord both expose lease_ref" do
      kr = %KeyRotationRecord{
        receipt_ref: "kr:1",
        key_ref: "secret:ssh_key:demo",
        rotated_at: DateTime.utc_now(),
        fingerprint: "SHA256:abc"
      }

      mr = %MaterializationRecord{
        receipt_ref: "mr:1",
        secret_ref: "secret:env:DEMO",
        lease_ref: "lease:env:DEMO",
        materialized_at: DateTime.utc_now()
      }

      assert is_binary(kr.fingerprint)
      assert is_binary(mr.lease_ref)
    end

    test "BoundaryRecord records decision and rationale" do
      r = %BoundaryRecord{
        receipt_ref: "br:1",
        protocol: "chassis.boundary.deploy.v1",
        decision: :allowed,
        rationale: "tenant=acme; residency=us-only"
      }

      assert r.decision == :allowed
    end

    test "TenantAwareDeploymentReceipt composes a DeploymentRecord and tenant guards" do
      view = %TenantAwareDeploymentReceipt{
        receipt_ref: "view:1",
        deployment_receipt_ref: "receipt:deployment:1",
        tenant_ref: "tenant:acme",
        residency_passed?: true,
        isolation_passed?: true
      }

      assert view.residency_passed?
      assert view.isolation_passed?
    end

    test "AITraceReceipt links chassis receipt to aitrace export ref" do
      r = %AITraceReceipt{
        receipt_ref: "ait:1",
        chassis_receipt_ref: "receipt:deployment:1",
        aitrace_export_ref: "aitrace:export:abc",
        exported_at: DateTime.utc_now()
      }

      assert r.chassis_receipt_ref == "receipt:deployment:1"
    end
  end

  describe "Chassis.Receipts.redact/1 generic helper" do
    test "masks any key whose name fragment matches the sensitive list" do
      redacted = Receipts.redact(%{password: "x", token: "y", visible: "ok"})
      assert redacted.password == "[REDACTED]"
      assert redacted.token == "[REDACTED]"
      assert redacted.visible == "ok"
    end

    test "redacts recursively through nested maps and lists" do
      redacted =
        Receipts.redact(%{
          labels: %{"secret_token" => "v"},
          items: [%{password: "p"}, %{ok: "ok"}]
        })

      assert redacted.labels["secret_token"] == "[REDACTED]"
      assert hd(redacted.items).password == "[REDACTED]"
      assert Enum.at(redacted.items, 1).ok == "ok"
    end
  end
end
