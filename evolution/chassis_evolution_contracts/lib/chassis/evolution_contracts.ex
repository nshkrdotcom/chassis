defmodule Chassis.Evolution.Refs do
  @moduledoc "Opaque ref string types used across Chassis Evolution."
  @type failure_batch_ref :: String.t()
  @type evidence_ref :: String.t()
  @type candidate_ref :: String.t()
  @type trial_ref :: String.t()
  @type trial_run_ref :: String.t()
  @type score_matrix_ref :: String.t()
  @type promotion_ref :: String.t()
  @type swap_ref :: String.t()
  @type rollback_ref :: String.t()
  @type operator_consent_ref :: String.t()
  @type code_agent_run_ref :: String.t()
  @type stage_artifact_ref :: String.t()
end

defmodule Chassis.Evolution.States do
  @moduledoc "Canonical evolution state set."
  @states [
    :queued,
    :evidence_curated,
    :planning,
    :patching,
    :building,
    :trial_provisioning,
    :trial_running,
    :scoring,
    :blocked,
    :converged,
    :awaiting_authority,
    :awaiting_operator_consent,
    :promotion_requested,
    :promoting,
    :committed,
    :rolled_back,
    :failed,
    :stopped
  ]
  @type t ::
          unquote(
            Enum.reduce(
              [
                :queued,
                :evidence_curated,
                :planning,
                :patching,
                :building,
                :trial_provisioning,
                :trial_running,
                :scoring,
                :blocked,
                :converged,
                :awaiting_authority,
                :awaiting_operator_consent,
                :promotion_requested,
                :promoting,
                :committed,
                :rolled_back,
                :failed,
                :stopped
              ],
              fn state, acc -> {:|, [], [state, acc]} end
            )
          )
  @spec all() :: [t()]
  def all, do: @states
  @spec terminal?(atom()) :: boolean()
  def terminal?(state), do: state in [:committed, :rolled_back, :failed, :stopped]
end

defmodule Chassis.Evolution.PromotionPreconditions do
  @moduledoc "Promotion precondition binding contract."
  @enforce_keys [
    :candidate_ref,
    :score_matrix_ref,
    :authority_ref,
    :operator_consent_ref,
    :rollback_manifest_ref,
    :health_probe_ref
  ]
  defstruct [
    :candidate_ref,
    :score_matrix_ref,
    :authority_ref,
    :operator_consent_ref,
    :rollback_manifest_ref,
    :health_probe_ref
  ]

  @type t :: %__MODULE__{}
end

for {name, fields} <- [
      {FailureBatch,
       [
         :failure_batch_ref,
         :tenant_ref,
         :installation_ref,
         :evidence_refs,
         :summary,
         :redaction_posture,
         :flagged_by_ref,
         :batch_hint_ref,
         :created_at
       ]},
      {CandidatePatch,
       [
         :candidate_ref,
         :base_release_ref,
         :base_image_digest,
         :patch_digest,
         :diff_ref,
         :failure_batch_ref,
         :code_agent_run_ref,
         :prompt_summary_ref,
         :created_at
       ]},
      {CandidateImage,
       [:candidate_ref, :artifact_kind, :digest, :built_at, :build_log_ref, :builder_ref]},
      {TrialRun,
       [
         :trial_run_ref,
         :trial_ref,
         :candidate_ref,
         :failure_batch_ref,
         :baseline_set_ref,
         :started_at,
         :completed_at,
         :verdict,
         :replay_log_ref
       ]},
      {ScoreMatrix,
       [
         :score_matrix_ref,
         :candidate_ref,
         :baseline_score,
         :candidate_score,
         :regression_gate,
         :confidence,
         :blocked_reasons,
         :scorer_receipts,
         :scorer_kind
       ]},
      {PromotionIntent,
       [
         :promotion_ref,
         :candidate_ref,
         :target_installation_ref,
         :issued_at,
         :consent_required?,
         :consent_ref_template
       ]},
      {PromotionReceipt,
       [:promotion_ref, :swap_ref, :outcome, :committed_at_or_rolled_back_at, :rollback_ref]},
      {RollbackReceipt,
       [:rollback_ref, :swap_ref, :restored_artifact_digest, :reason_code, :rolled_back_at]},
      {OperatorConsent,
       [
         :operator_consent_ref,
         :candidate_ref,
         :decision,
         :recorded_at,
         :actor_ref,
         :justification_summary,
         :lower_read_lease_ref
       ]},
      {CodeAgentRun,
       [
         :code_agent_run_ref,
         :runner_kind,
         :candidate_ref,
         :failure_batch_ref,
         :started_at,
         :completed_at,
         :exit_status,
         :prompt_summary_ref,
         :diff_ref,
         :cost_ref,
         :token_ref,
         :log_ref
       ]},
      {StageArtifact, [:stage_artifact_ref, :kind, :digest, :bytes, :stored_at_ref]}
    ] do
  defmodule Module.concat(Chassis.Evolution.DTO, name) do
    @moduledoc "Evolution DTO."
    defstruct fields
    @type t :: %__MODULE__{}
    @spec new(map()) :: t()
    def new(attrs), do: struct(__MODULE__, attrs)
  end
end

defmodule Chassis.Evolution.CodingAgentRunner do
  @moduledoc "External coding-agent runner behaviour."
  @callback spawn_run(map(), keyword()) :: {:ok, map()} | {:error, term()}
end

defmodule Chassis.Evolution.Scorer do
  @moduledoc "Candidate scorer behaviour."
  @callback score(map(), keyword()) :: {:ok, map()} | {:error, term()}
end

defmodule Chassis.Evolution.TrialProvider do
  @moduledoc "Trial provider behaviour."
  @callback provision(map(), keyword()) :: {:ok, map()} | {:error, term()}
end

defmodule Chassis.Evolution.PromotionExecutor do
  @moduledoc "Promotion executor behaviour."
  @callback promote(map(), keyword()) :: {:ok, map()} | {:error, term()}
  @callback rollback(map(), keyword()) :: {:ok, map()} | {:error, term()}
end
