defmodule Chassis.Evolution.ReceiptsTest do
  use ExUnit.Case, async: true

  alias Chassis.Evolution.Receipts.FailureBatchRecord
  alias Chassis.Evolution.Receipts.Store.Memory

  @raw_transcript "RAW TRANSCRIPT SECRET phase23 receipt leak"

  test "FailureBatchRecord enforces required fields and redacts raw payloads" do
    attrs = failure_batch_attrs()

    assert %FailureBatchRecord{} = record = FailureBatchRecord.new!(attrs)
    assert record.receipt_ref == "receipt:failure_batch:failure_batch:phase23"
    assert record.summary.bytes == "bounded summary"
    refute inspect(record) =~ @raw_transcript

    assert_raise ArgumentError, ~r/missing required evolution field failure_batch_ref/, fn ->
      attrs |> Map.delete(:failure_batch_ref) |> FailureBatchRecord.new!()
    end
  end

  test "Memory store can put, get, and list FailureBatchRecord rows without raw transcript bytes" do
    {:ok, store} = Memory.start_link(name: nil)
    record = FailureBatchRecord.new!(failure_batch_attrs())

    assert {:ok, stored} = Memory.put(store, record)
    assert {:ok, ^stored} = Memory.get(store, stored.receipt_ref)
    assert [^stored] = Memory.list(store)
    refute inspect(Memory.list(store)) =~ @raw_transcript
  end

  test "future receipt records are explicit not_implemented placeholders in Phase 23" do
    future_modules = [
      Chassis.Evolution.Receipts.CandidatePatchRecord,
      Chassis.Evolution.Receipts.CodingAgentRunRecord,
      Chassis.Evolution.Receipts.TrialRunRecord,
      Chassis.Evolution.Receipts.ScoreMatrixRecord,
      Chassis.Evolution.Receipts.PromotionIntentRecord,
      Chassis.Evolution.Receipts.PromotionRecord,
      Chassis.Evolution.Receipts.SwapRecord,
      Chassis.Evolution.Receipts.EvolutionRollbackRecord,
      Chassis.Evolution.Receipts.OperatorConsentRecord,
      Chassis.Evolution.Receipts.EvolutionStartRecord,
      Chassis.Evolution.Receipts.EvolutionStopRecord
    ]

    for module <- future_modules do
      assert {:error, {:not_implemented, ^module}} = module.put(%{})
    end
  end

  defp failure_batch_attrs do
    %{
      failure_batch_ref: "failure_batch:phase23",
      tenant_ref: "tenant:dev",
      installation_ref: "installation:dev",
      source: :mezzanine,
      evidence_refs: ["evidence:phase23"],
      summary: %{bytes: "bounded summary", max_bytes: 512},
      redaction_posture: :default,
      raw_transcript: @raw_transcript,
      inserted_at: ~U[2026-01-01 00:00:00Z]
    }
  end
end
