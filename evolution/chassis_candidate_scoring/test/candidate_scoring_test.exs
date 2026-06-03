defmodule Chassis.Candidate.ScoringTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Chassis.Candidate.Scoring
  alias Chassis.Evolution.DTO.{ScoreMatrix, TrialRun}
  alias Chassis.Evolution.Receipts.Store.Memory, as: ReceiptStore

  defmodule BehaviourScorer do
    @behaviour Chassis.Evolution.Scorer

    @impl true
    def score_trial(trial_run, opts) do
      send(Keyword.fetch!(opts, :caller), {:scored, trial_run.trial_run_ref})

      {:ok,
       ScoreMatrix.new!(%{
         score_matrix_ref: "score:#{trial_run.candidate_ref}",
         candidate_ref: trial_run.candidate_ref,
         baseline_score: Keyword.get(opts, :baseline_score, 0.80),
         candidate_score: Keyword.get(opts, :candidate_score, 0.92),
         regression_gate: :passed,
         confidence: Keyword.get(opts, :confidence, 0.91),
         blocked_reasons: Keyword.get(opts, :blocked_reasons, []),
         scorer_receipts: Keyword.get(opts, :scorer_receipts, []),
         scorer_kind: :test_behaviour
       })}
    end
  end

  test "score_trial delegates score production to a Scorer behaviour implementation" do
    trial = trial_run()

    assert {:ok, matrix} =
             Scoring.score_trial(trial, scorer: BehaviourScorer, caller: self())

    assert_received {:scored, "trial_run:dev:smoke"}
    assert matrix.regression_gate == :passed
    assert matrix.blocked_reasons == []
    assert matrix.scorer_kind == :test_behaviour
  end

  test "any baseline regression blocks the gate" do
    assert {:ok, matrix} =
             Scoring.score_trial(trial_run(),
               scorer: BehaviourScorer,
               caller: self(),
               baseline_score: 0.90,
               candidate_score: 0.899
             )

    assert matrix.regression_gate == :blocked
    assert :baseline_regression in matrix.blocked_reasons
  end

  test "confidence below threshold blocks the gate" do
    assert {:ok, matrix} =
             Scoring.score_trial(trial_run(),
               scorer: BehaviourScorer,
               caller: self(),
               confidence: 0.79,
               min_confidence: 0.80
             )

    assert matrix.regression_gate == :blocked
    assert :confidence_below_threshold in matrix.blocked_reasons
  end

  test "required evidence subset must pass" do
    receipts = [
      %{evidence_ref: "ev:one", verdict: :passed},
      %{evidence_ref: "ev:two", verdict: :failed}
    ]

    assert {:ok, matrix} =
             Scoring.score_trial(trial_run(),
               scorer: BehaviourScorer,
               caller: self(),
               required_evidence_refs: ["ev:one", "ev:two"],
               scorer_receipts: receipts
             )

    assert matrix.regression_gate == :blocked
    assert :evidence_subset_failed in matrix.blocked_reasons
  end

  test "blocked reasons are enforced as a closed set" do
    assert {:error, {:unknown_blocked_reasons, [:not_allowed]}} =
             Scoring.score_trial(trial_run(),
               scorer: BehaviourScorer,
               caller: self(),
               blocked_reasons: [:not_allowed]
             )
  end

  test "score matrices are recorded when a receipt store is supplied" do
    {:ok, store} = ReceiptStore.start_link(name: nil)

    assert {:ok, matrix} =
             Scoring.score_trial(trial_run(),
               scorer: BehaviourScorer,
               caller: self(),
               receipt_store: store
             )

    assert {:ok, receipt} =
             ReceiptStore.get(store, "receipt:score_matrix:#{matrix.score_matrix_ref}")

    assert receipt.score_matrix_ref == matrix.score_matrix_ref
    assert receipt.regression_gate == :passed
  end

  test "package-local Mix task emits structural score JSON" do
    Mix.Task.reenable("chassis.evolution.score.show")

    output =
      capture_io(fn ->
        Mix.Tasks.Chassis.Evolution.Score.Show.run([
          "--candidate-ref",
          "cand:dev:smoke",
          "--json"
        ])
      end)

    assert {:ok, decoded} = Jason.decode(output)
    assert decoded["candidate_ref"] == "cand:dev:smoke"
    assert decoded["regression_gate"] == "passed"
  end

  defp trial_run do
    TrialRun.new!(%{
      trial_run_ref: "trial_run:dev:smoke",
      trial_ref: "trial:cand:dev:smoke",
      candidate_ref: "cand:dev:smoke",
      failure_batch_ref: "failure_batch:dev:smoke",
      baseline_set_ref: "baseline:dev:smoke",
      started_at: DateTime.utc_now(),
      completed_at: DateTime.utc_now(),
      verdict: :passed,
      replay_log_ref: "replay:dev:smoke"
    })
  end
end
