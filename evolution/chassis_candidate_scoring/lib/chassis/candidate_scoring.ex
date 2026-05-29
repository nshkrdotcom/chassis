defmodule Chassis.Candidate.Scoring do
  @moduledoc "Candidate score matrix and regression gate."
  @blocked_reasons [:baseline_regression, :confidence_below_threshold, :evidence_subset_failed]
  @spec score(map(), keyword()) :: {:ok, map()}
  def score(attrs, opts \\ []) do
    baseline = Keyword.get(opts, :baseline_score, 1.0)
    candidate = Keyword.get(opts, :candidate_score, baseline)
    confidence = Keyword.get(opts, :confidence, 1.0)
    blocked = candidate < baseline or confidence < 0.8

    {:ok,
     %{
       score_matrix_ref: "score:cand:dev:smoke",
       candidate_ref: Map.get(attrs, :candidate_ref, "cand:dev:smoke"),
       baseline_score: baseline,
       candidate_score: candidate,
       confidence: confidence,
       regression_gate: if(blocked, do: :blocked, else: :passed),
       blocked_reasons: if(blocked, do: [:baseline_regression], else: [])
     }}
  end

  @spec blocked_reasons() :: [atom()]
  def blocked_reasons, do: @blocked_reasons
end
