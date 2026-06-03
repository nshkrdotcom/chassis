defmodule Chassis.Candidate.Scoring do
  @moduledoc "Candidate score matrix and regression gate."

  @behaviour Chassis.Evolution.Scorer

  alias Chassis.Evolution.DTO.{ScoreMatrix, TrialRun}
  alias Chassis.Evolution.Receipts.ScoreMatrixRecord
  alias Chassis.Evolution.Receipts.Store.Memory, as: ReceiptStore

  @blocked_reasons [:baseline_regression, :confidence_below_threshold, :evidence_subset_failed]

  @spec score(map(), keyword()) :: {:ok, ScoreMatrix.t()} | {:error, term()}
  def score(attrs, opts \\ []) do
    attrs
    |> trial_run_from_attrs()
    |> score_trial(opts)
  end

  @impl true
  def score_trial(%TrialRun{} = trial_run, opts) do
    scorer = Keyword.get(opts, :scorer, Chassis.Candidate.Scoring.FixtureScorer)
    scorer_opts = Keyword.drop(opts, [:scorer, :receipt_store, :min_confidence])

    with {:ok, %ScoreMatrix{} = matrix} <- scorer.score_trial(trial_run, scorer_opts),
         {:ok, gated} <- apply_regression_gate(matrix, trial_run, opts),
         {:ok, _recorded} <- maybe_record(gated, opts) do
      {:ok, gated}
    end
  end

  @spec show(String.t(), keyword()) :: {:ok, ScoreMatrix.t()} | {:error, term()}
  def show(candidate_ref, opts \\ []) when is_binary(candidate_ref) do
    score(%{candidate_ref: candidate_ref}, opts)
  end

  @spec jsonable(ScoreMatrix.t()) :: map()
  def jsonable(%ScoreMatrix{} = matrix) do
    %{
      score_matrix_ref: matrix.score_matrix_ref,
      candidate_ref: matrix.candidate_ref,
      baseline_score: matrix.baseline_score,
      candidate_score: matrix.candidate_score,
      regression_gate: Atom.to_string(matrix.regression_gate),
      confidence: matrix.confidence,
      blocked_reasons: Enum.map(matrix.blocked_reasons || [], &Atom.to_string/1),
      scorer_kind: Atom.to_string(matrix.scorer_kind)
    }
  end

  @spec blocked_reasons() :: [atom()]
  def blocked_reasons, do: @blocked_reasons

  defp apply_regression_gate(%ScoreMatrix{} = matrix, %TrialRun{} = trial_run, opts) do
    with :ok <- validate_blocked_reasons(matrix.blocked_reasons || []) do
      computed =
        []
        |> maybe_add(matrix.candidate_score < matrix.baseline_score, :baseline_regression)
        |> maybe_add(
          matrix.confidence < Keyword.get(opts, :min_confidence, 0.80),
          :confidence_below_threshold
        )
        |> maybe_add(evidence_subset_failed?(trial_run, matrix, opts), :evidence_subset_failed)

      reasons = Enum.uniq((matrix.blocked_reasons || []) ++ computed)
      gate = if reasons == [], do: :passed, else: :blocked

      matrix
      |> Map.from_struct()
      |> Map.put(:blocked_reasons, reasons)
      |> Map.put(:regression_gate, gate)
      |> ScoreMatrix.new!()
      |> then(&{:ok, &1})
    end
  end

  defp validate_blocked_reasons(reasons) do
    unknown = Enum.reject(reasons, &(&1 in @blocked_reasons))

    case unknown do
      [] -> :ok
      reasons -> {:error, {:unknown_blocked_reasons, reasons}}
    end
  end

  defp maybe_add(reasons, true, reason), do: [reason | reasons]
  defp maybe_add(reasons, false, _reason), do: reasons

  defp evidence_subset_failed?(%TrialRun{} = trial_run, %ScoreMatrix{} = matrix, opts) do
    trial_failed? = trial_run.verdict not in [:passed, :pass, :ok]
    required = Keyword.get(opts, :required_evidence_refs, [])
    receipts = matrix.scorer_receipts || []

    subset_failed? =
      required != [] and
        Enum.any?(required, fn evidence_ref ->
          not Enum.any?(receipts, &receipt_passed?(&1, evidence_ref))
        end)

    trial_failed? or subset_failed?
  end

  defp receipt_passed?(receipt, evidence_ref) when is_map(receipt) do
    ref = Map.get(receipt, :evidence_ref) || Map.get(receipt, "evidence_ref")
    verdict = Map.get(receipt, :verdict) || Map.get(receipt, "verdict")
    ref == evidence_ref and verdict in [:passed, :pass, :ok, "passed", "pass", "ok"]
  end

  defp receipt_passed?(_receipt, _evidence_ref), do: false

  defp maybe_record(%ScoreMatrix{} = matrix, opts) do
    case Keyword.get(opts, :receipt_store) do
      nil ->
        {:ok, nil}

      store ->
        record =
          matrix
          |> Map.from_struct()
          |> Map.put_new(:tenant_ref, Keyword.get(opts, :tenant_ref, "tenant:dev"))
          |> Map.put_new(
            :installation_ref,
            Keyword.get(opts, :installation_ref, "installation:dev")
          )
          |> Map.put_new(
            :trace_id,
            Keyword.get(opts, :trace_id, "trace:score:#{matrix.candidate_ref}")
          )
          |> ScoreMatrixRecord.new!()

        with {:ok, receipt} <- ReceiptStore.put(store, record) do
          {:ok, receipt}
        end
    end
  end

  defp trial_run_from_attrs(attrs) when is_map(attrs) do
    candidate_ref = Map.get(attrs, :candidate_ref, "cand:dev:smoke")

    TrialRun.new!(%{
      trial_run_ref: Map.get(attrs, :trial_run_ref, "trial_run:#{candidate_ref}"),
      trial_ref: Map.get(attrs, :trial_ref, "trial:#{candidate_ref}"),
      candidate_ref: candidate_ref,
      failure_batch_ref: Map.get(attrs, :failure_batch_ref, "failure_batch:dev:smoke"),
      baseline_set_ref: Map.get(attrs, :baseline_set_ref, "baseline:dev:smoke"),
      started_at: Map.get(attrs, :started_at, DateTime.utc_now()),
      completed_at: Map.get(attrs, :completed_at, DateTime.utc_now()),
      verdict: Map.get(attrs, :verdict, :passed),
      replay_log_ref: Map.get(attrs, :replay_log_ref, "replay:dev:smoke")
    })
  end
end

defmodule Chassis.Candidate.Scoring.FixtureScorer do
  @moduledoc "Deterministic scorer adapter for package smoke and local development."

  @behaviour Chassis.Evolution.Scorer

  alias Chassis.Evolution.DTO.{ScoreMatrix, TrialRun}

  @impl true
  def score_trial(%TrialRun{} = trial_run, opts) do
    scorer_receipts =
      Keyword.get(opts, :scorer_receipts, [
        %{evidence_ref: trial_run.replay_log_ref, verdict: trial_run.verdict}
      ])

    {:ok,
     ScoreMatrix.new!(%{
       score_matrix_ref: Keyword.get(opts, :score_matrix_ref, "score:#{trial_run.candidate_ref}"),
       candidate_ref: trial_run.candidate_ref,
       baseline_score: Keyword.get(opts, :baseline_score, 0.80),
       candidate_score: Keyword.get(opts, :candidate_score, 0.92),
       regression_gate: :passed,
       confidence: Keyword.get(opts, :confidence, 0.91),
       blocked_reasons: Keyword.get(opts, :blocked_reasons, []),
       scorer_receipts: scorer_receipts,
       scorer_kind: :fixture
     })}
  end
end
