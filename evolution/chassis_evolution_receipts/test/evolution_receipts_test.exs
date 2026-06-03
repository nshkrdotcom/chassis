defmodule Chassis.Evolution.ReceiptsTest do
  use ExUnit.Case, async: false

  alias Chassis.Evolution.Receipts
  alias Chassis.Evolution.Receipts.AfterActions.Recorder

  alias Chassis.Evolution.Receipts.{
    CandidatePatchRecord,
    CodingAgentRunRecord,
    EvolutionRollbackRecord,
    EvolutionStartRecord,
    EvolutionStopRecord,
    FailureBatchRecord,
    OperatorConsentRecord,
    PromotionIntentRecord,
    PromotionRecord,
    ScoreMatrixRecord,
    SwapRecord,
    TrialRunRecord
  }

  alias Chassis.Evolution.Receipts.Store.{AshPostgres, Memory}

  @raw_transcript "RAW TRANSCRIPT SECRET phase23 receipt leak"
  @raw_provider_token "PROVIDER TOKEN SECRET phase24 receipt leak"

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

  test "Phase 24 lifecycle receipt records build typed redacted rows" do
    for {module, attrs} <- lifecycle_receipt_cases() do
      attrs = Map.put(attrs, :raw_provider_token, @raw_provider_token)
      assert %{__struct__: ^module} = record = module.new!(attrs)
      assert is_binary(record.receipt_ref)
      assert record.tenant_ref == "tenant:dev"
      refute inspect(record) =~ @raw_provider_token

      first_required = hd(module.required_fields())

      assert_raise ArgumentError, ~r/missing required evolution field/, fn ->
        attrs |> Map.delete(first_required) |> module.new!()
      end
    end
  end

  test "receipt store after_action fires AITrace, Observability, Mezzanine, and AppKit stubs" do
    {:ok, recorder} = Recorder.start_link(name: nil)

    {:ok, store} =
      Memory.start_link(name: nil, after_actions: Receipts.AfterActions.stub_callbacks(recorder))

    record = CandidatePatchRecord.new!(candidate_patch_attrs())
    assert {:ok, _stored} = Memory.put(store, record)

    events = Recorder.list(recorder)

    assert Enum.map(events, & &1.surface) == [
             :aitrace,
             :observability,
             :mezzanine_outbox,
             :appkit_projection
           ]

    assert Enum.all?(events, &(&1.receipt_ref == record.receipt_ref))
    refute inspect(events) =~ @raw_provider_token
  end

  test "Memory and AshPostgres stores provide parity for lifecycle records" do
    {:ok, memory} = Memory.start_link(name: nil)
    {:ok, ash} = AshPostgres.start_link(name: nil)
    record = CandidatePatchRecord.new!(candidate_patch_attrs())

    assert {:ok, memory_record} = Memory.put(memory, record)
    assert {:ok, ash_record} = AshPostgres.put(ash, record)

    assert Map.from_struct(memory_record) == Map.from_struct(ash_record)
    assert {:ok, ^memory_record} = Memory.get(memory, record.receipt_ref)
    assert {:ok, ^ash_record} = AshPostgres.get(ash, record.receipt_ref)

    assert Memory.list(memory, kind: CandidatePatchRecord) ==
             AshPostgres.list(ash, kind: CandidatePatchRecord)
  end

  defp lifecycle_receipt_cases do
    [
      {CandidatePatchRecord, candidate_patch_attrs()},
      {CodingAgentRunRecord,
       base_attrs(:coding_agent_run)
       |> Map.merge(%{
         code_agent_run_ref: "code-agent-run:phase24",
         runner_kind: :custom,
         candidate_ref: "cand:phase24",
         started_at: ~U[2026-01-01 00:00:00Z]
       })},
      {TrialRunRecord,
       base_attrs(:trial_run)
       |> Map.merge(%{
         trial_run_ref: "trial-run:phase24",
         trial_ref: "trial:phase24",
         candidate_ref: "cand:phase24",
         started_at: ~U[2026-01-01 00:00:00Z]
       })},
      {ScoreMatrixRecord,
       base_attrs(:score_matrix)
       |> Map.merge(%{
         score_matrix_ref: "score-matrix:phase24",
         candidate_ref: "cand:phase24",
         regression_gate: :passed,
         confidence: 0.91
       })},
      {PromotionIntentRecord,
       base_attrs(:promotion_intent)
       |> Map.merge(%{
         promotion_ref: "promotion:phase24",
         candidate_ref: "cand:phase24",
         target_installation_ref: "installation:prod",
         issued_at: ~U[2026-01-01 00:00:00Z]
       })},
      {PromotionRecord,
       base_attrs(:promotion)
       |> Map.merge(%{
         promotion_ref: "promotion:phase24",
         swap_ref: "swap:phase24",
         outcome: :committed,
         committed_at_or_rolled_back_at: ~U[2026-01-01 00:00:00Z]
       })},
      {SwapRecord,
       base_attrs(:swap)
       |> Map.merge(%{
         swap_ref: "swap:phase24",
         candidate_ref: "cand:phase24",
         target_installation_ref: "installation:prod",
         artifact_digest: "sha256:artifact"
       })},
      {EvolutionRollbackRecord,
       base_attrs(:evolution_rollback)
       |> Map.merge(%{
         rollback_ref: "rollback:phase24",
         swap_ref: "swap:phase24",
         restored_artifact_digest: "sha256:previous",
         rolled_back_at: ~U[2026-01-01 00:00:00Z]
       })},
      {OperatorConsentRecord,
       base_attrs(:operator_consent)
       |> Map.merge(%{
         operator_consent_ref: "operator-consent:phase24",
         candidate_ref: "cand:phase24",
         decision: :approved,
         recorded_at: ~U[2026-01-01 00:00:00Z],
         actor_ref: "operator:phase24"
       })},
      {EvolutionStartRecord,
       base_attrs(:evolution_start)
       |> Map.merge(%{
         evolution_run_ref: "evolution-run:phase24",
         failure_batch_ref: "failure_batch:phase24",
         started_at: ~U[2026-01-01 00:00:00Z]
       })},
      {EvolutionStopRecord,
       base_attrs(:evolution_stop)
       |> Map.merge(%{
         evolution_run_ref: "evolution-run:phase24",
         stopped_at: ~U[2026-01-01 00:00:00Z],
         reason_code: :operator_stop
       })}
    ]
  end

  defp candidate_patch_attrs do
    base_attrs(:candidate_patch)
    |> Map.merge(%{
      candidate_ref: "cand:phase24",
      base_release_ref: "release:base:phase24",
      patch_digest: "sha256:patch",
      diff_ref: "diff:phase24",
      failure_batch_ref: "failure_batch:phase24"
    })
  end

  defp base_attrs(kind) do
    %{
      tenant_ref: "tenant:dev",
      installation_ref: "installation:dev",
      trace_id: "trace:phase24",
      receipt_kind: kind,
      summary: %{bytes: "bounded #{kind} summary", max_bytes: 256},
      inserted_at: ~U[2026-01-01 00:00:00Z]
    }
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
