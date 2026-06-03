defmodule Chassis.Candidate.RegistryTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Chassis.Candidate.Registry
  alias Chassis.Candidate.Registry.Entry
  alias Chassis.Candidate.Registry.Store.{AshPostgres, Memory}
  alias Chassis.Evolution.Receipts.CandidatePatchRecord
  alias Chassis.Evolution.Receipts.Store.Memory, as: ReceiptMemory

  @raw_prompt "RAW PROVIDER PROMPT phase24 should never be stored"

  setup do
    {:ok, store} = Memory.start_link(name: nil)
    {:ok, ash_store} = AshPostgres.start_link(name: nil)
    {:ok, receipt_store} = ReceiptMemory.start_link(name: nil)
    %{store: store, ash_store: ash_store, receipt_store: receipt_store}
  end

  test "register/get/list and attach operations maintain lifecycle fields and write receipts", %{
    store: store,
    receipt_store: receipt_store
  } do
    assert {:ok, %Entry{} = entry} =
             Registry.register(candidate_attrs(), store: store, receipts_store: receipt_store)

    assert entry.candidate_ref == "cand:dev:smoke"
    assert entry.tenant_ref == "tenant:dev"
    assert entry.last_state == :patching
    refute contains_raw?(entry)

    assert {:ok, ^entry} = Registry.get("cand:dev:smoke", store: store)
    assert [^entry] = Registry.list(tenant_ref: "tenant:dev", store: store)
    assert [] = Registry.list(tenant_ref: "tenant:other", store: store)

    assert {:ok, state_entry} =
             Registry.update_state("cand:dev:smoke", :scoring,
               store: store,
               receipts_store: receipt_store
             )

    assert state_entry.last_state == :scoring

    assert {:ok, image_entry} =
             Registry.attach_digest("cand:dev:smoke", :candidate_image_digest, "sha256:image",
               store: store,
               receipts_store: receipt_store
             )

    assert image_entry.candidate_image_digest == "sha256:image"

    assert {:ok, scored_entry} =
             Registry.attach_score_matrix("cand:dev:smoke", "score:matrix:dev",
               store: store,
               receipts_store: receipt_store
             )

    assert scored_entry.score_matrix_ref == "score:matrix:dev"

    assert {:ok, authority_entry} =
             Registry.attach_authority("cand:dev:smoke", "authority:dev",
               store: store,
               receipts_store: receipt_store
             )

    assert authority_entry.authority_ref == "authority:dev"

    assert {:ok, consent_entry} =
             Registry.attach_consent("cand:dev:smoke", "consent:dev",
               store: store,
               receipts_store: receipt_store
             )

    assert consent_entry.operator_consent_ref == "consent:dev"

    assert {:ok, swap_entry} =
             Registry.attach_swap("cand:dev:smoke", "promotion:receipt:dev",
               store: store,
               receipts_store: receipt_store
             )

    assert swap_entry.promotion_receipt_ref == "promotion:receipt:dev"

    assert {:ok, rollback_entry} =
             Registry.attach_rollback("cand:dev:smoke", "rollback:dev",
               store: store,
               receipts_store: receipt_store
             )

    assert rollback_entry.rollback_ref == "rollback:dev"

    assert {:error, {:invalid_state, :not_a_state}} =
             Registry.update_state("cand:dev:smoke", :not_a_state, store: store)

    receipts = ReceiptMemory.list(receipt_store)

    assert Enum.any?(
             receipts,
             &match?(%CandidatePatchRecord{candidate_ref: "cand:dev:smoke"}, &1)
           )

    refute contains_raw?(receipts)
  end

  test "Memory and AshPostgres facades preserve the same candidate contract", %{
    store: memory_store,
    ash_store: ash_store,
    receipt_store: receipt_store
  } do
    assert {:ok, memory_entry} =
             Registry.register(candidate_attrs("cand:memory"),
               store: memory_store,
               receipts_store: receipt_store
             )

    assert {:ok, ash_entry} =
             Registry.register(candidate_attrs("cand:ash"),
               store: ash_store,
               receipts_store: receipt_store
             )

    assert Map.keys(Entry.ash_resource_schema().fields) |> Enum.sort() ==
             Entry.fields() |> Enum.sort()

    assert scrub_ref(memory_entry) == scrub_ref(ash_entry)
  end

  test "package-local Mix task shows candidates as structural JSON" do
    Mix.Task.reenable("chassis.evolution.candidate.show")

    output =
      capture_io(fn ->
        Mix.Tasks.Chassis.Evolution.Candidate.Show.run([
          "--candidate-ref",
          "cand:dev:smoke",
          "--json"
        ])
      end)

    assert {:ok, decoded} = Jason.decode(output)
    assert decoded["candidate_ref"] == "cand:dev:smoke"
    assert decoded["tenant_ref"] == "tenant:dev"
    refute contains_raw?(decoded)
  end

  defp candidate_attrs(candidate_ref \\ "cand:dev:smoke") do
    %{
      candidate_ref: candidate_ref,
      tenant_ref: "tenant:dev",
      installation_ref: "installation:dev",
      base_release_ref: "release:base:dev",
      base_image_digest: "sha256:base",
      patch_digest: "sha256:patch",
      failure_batch_ref: "failure_batch:phase24",
      trace_id: "trace:phase24",
      last_state: :patching,
      raw_prompt: @raw_prompt,
      raw_diff: "RAW DIFF phase24 should never be stored"
    }
  end

  defp scrub_ref(%Entry{} = entry) do
    entry
    |> Map.from_struct()
    |> Map.put(:candidate_ref, "cand:normalized")
    |> Map.delete(:created_at)
    |> Map.delete(:updated_at)
  end

  defp contains_raw?(value), do: inspect(value) =~ @raw_prompt
end
