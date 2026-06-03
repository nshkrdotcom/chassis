defmodule Chassis.Evolution.ContractsTest do
  use ExUnit.Case, async: true

  alias Chassis.Evolution.PromotionPreconditions
  alias Chassis.Evolution.States
  alias Chassis.Evolution.DTO

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

  @terminal_states [:committed, :rolled_back, :failed, :stopped]

  @promotion_precondition_fields [
    :candidate_ref,
    :failure_batch_ref,
    :patch_digest,
    :artifact_digest,
    :score_matrix_ref,
    :regression_gate,
    :authority_ref,
    :operator_consent_ref,
    :rollback_ref,
    :target_installation_ref,
    :approved_state_volume_mounts,
    :trace_id
  ]

  test "States exposes the canonical 18-state set and terminal truth table" do
    assert States.all() == @states
    assert length(States.all()) == 18

    for state <- @states do
      assert States.terminal?(state) == state in @terminal_states
    end

    refute States.terminal?(:unknown)
  end

  test "PromotionPreconditions requires every authority, rollback, target, and trace field" do
    attrs =
      Map.new(@promotion_precondition_fields, fn
        :approved_state_volume_mounts -> {:approved_state_volume_mounts, ["volume:dev:state"]}
        :regression_gate -> {:regression_gate, :passed}
        field -> {field, "#{field}:phase22"}
      end)

    assert PromotionPreconditions.required_fields() == @promotion_precondition_fields
    assert %PromotionPreconditions{} = PromotionPreconditions.new!(attrs)

    for field <- @promotion_precondition_fields do
      invalid = Map.delete(attrs, field)

      assert_raise ArgumentError, ~r/missing required evolution field #{field}/, fn ->
        PromotionPreconditions.new!(invalid)
      end
    end
  end

  test "behaviours expose the exact callback contracts from the lifecycle spec" do
    assert callbacks(Chassis.Evolution.CodingAgentRunner) == [cancel_run: 2, spawn_run: 2]
    assert callbacks(Chassis.Evolution.Scorer) == [score_trial: 2]
    assert callbacks(Chassis.Evolution.TrialProvider) == [provision_trial: 3, teardown_trial: 2]
    assert callbacks(Chassis.Evolution.PromotionExecutor) == [execute_swap: 2, rollback_swap: 2]
  end

  test "every DTO enforces required fields and round-trips through JSON as a struct" do
    for {module, required_fields, attrs} <- dto_cases() do
      assert module.required_fields() == required_fields
      struct = module.new!(attrs)

      assert {:ok, json} = module.to_json(struct)
      assert is_binary(json)
      assert {:ok, ^struct} = module.from_json(json)

      for field <- required_fields do
        invalid = Map.delete(attrs, field)

        assert_raise ArgumentError, ~r/missing required evolution field #{field}/, fn ->
          module.new!(invalid)
        end
      end

      assert {:error, {:invalid_json, _reason}} = module.from_json("{not-json")

      assert {:error, {:unknown_fields, [:unexpected]}} =
               module.from_json(~s({"unexpected":true}))
    end
  end

  defp callbacks(module), do: module.behaviour_info(:callbacks) |> Enum.sort()

  defp dto_cases do
    [
      {DTO.FailureBatch,
       [
         :failure_batch_ref,
         :tenant_ref,
         :installation_ref,
         :evidence_refs,
         :summary,
         :redaction_posture,
         :created_at
       ],
       %{
         failure_batch_ref: "failure_batch:phase22",
         tenant_ref: "tenant:dev",
         installation_ref: "installation:dev",
         evidence_refs: ["evidence:span:1", "evidence:receipt:2"],
         summary: %{bytes: "bounded summary", max_bytes: 512},
         redaction_posture: :strict,
         flagged_by_ref: "operator:phase22",
         batch_hint_ref: "hint:phase22",
         created_at: at(1)
       }},
      {DTO.CandidatePatch, [:candidate_ref, :base_release_ref, :patch_digest, :diff_ref],
       %{
         candidate_ref: "candidate:phase22",
         base_release_ref: "release:base",
         base_image_digest: "sha256:base",
         patch_digest: "sha256:patch",
         diff_ref: "stage_artifact:diff:phase22",
         failure_batch_ref: "failure_batch:phase22",
         code_agent_run_ref: "code_agent_run:phase22",
         prompt_summary_ref: "stage_artifact:prompt:phase22",
         created_at: at(2)
       }},
      {DTO.CandidateImage, [:candidate_ref, :artifact_kind, :digest, :built_at],
       %{
         candidate_ref: "candidate:phase22",
         artifact_kind: :container_image,
         digest: "sha256:image",
         built_at: at(3),
         build_log_ref: "stage_artifact:build_log:phase22",
         builder_ref: "builder:local"
       }},
      {DTO.TrialRun, [:trial_run_ref, :trial_ref, :candidate_ref, :started_at],
       %{
         trial_run_ref: "trial_run:phase22",
         trial_ref: "trial:phase22",
         candidate_ref: "candidate:phase22",
         failure_batch_ref: "failure_batch:phase22",
         baseline_set_ref: "baseline:phase22",
         started_at: at(4),
         completed_at: at(5),
         verdict: :ok,
         replay_log_ref: "stage_artifact:replay:phase22"
       }},
      {DTO.ScoreMatrix,
       [
         :score_matrix_ref,
         :candidate_ref,
         :baseline_score,
         :candidate_score,
         :regression_gate,
         :confidence
       ],
       %{
         score_matrix_ref: "score_matrix:phase22",
         candidate_ref: "candidate:phase22",
         baseline_score: 0.91,
         candidate_score: 0.94,
         regression_gate: :passed,
         confidence: 0.88,
         blocked_reasons: [:flake_budget],
         scorer_receipts: ["receipt:score:phase22"],
         scorer_kind: :stack_lab
       }},
      {DTO.PromotionIntent,
       [:promotion_ref, :candidate_ref, :target_installation_ref, :issued_at],
       %{
         promotion_ref: "promotion:phase22",
         candidate_ref: "candidate:phase22",
         target_installation_ref: "installation:dev",
         issued_at: at(6),
         consent_required?: true,
         consent_ref_template: "consent:phase22:{candidate_ref}"
       }},
      {DTO.PromotionReceipt,
       [:promotion_ref, :swap_ref, :outcome, :committed_at_or_rolled_back_at],
       %{
         promotion_ref: "promotion:phase22",
         swap_ref: "swap:phase22",
         outcome: :committed,
         committed_at_or_rolled_back_at: at(7),
         rollback_ref: "rollback:phase22"
       }},
      {DTO.RollbackReceipt,
       [:rollback_ref, :swap_ref, :restored_artifact_digest, :rolled_back_at],
       %{
         rollback_ref: "rollback:phase22",
         swap_ref: "swap:phase22",
         restored_artifact_digest: "sha256:restored",
         reason_code: :health_probe_failed,
         rolled_back_at: at(8)
       }},
      {DTO.OperatorConsent,
       [:operator_consent_ref, :candidate_ref, :decision, :recorded_at, :actor_ref],
       %{
         operator_consent_ref: "operator_consent:phase22",
         candidate_ref: "candidate:phase22",
         decision: :approve,
         recorded_at: at(9),
         actor_ref: "operator:phase22",
         justification_summary: "bounded approval",
         lower_read_lease_ref: "lease:phase22"
       }},
      {DTO.CodeAgentRun, [:code_agent_run_ref, :runner_kind, :candidate_ref, :started_at],
       %{
         code_agent_run_ref: "code_agent_run:phase22",
         runner_kind: :codex,
         candidate_ref: "candidate:phase22",
         failure_batch_ref: "failure_batch:phase22",
         started_at: at(10),
         completed_at: at(11),
         exit_status: :ok,
         prompt_summary_ref: "stage_artifact:prompt:phase22",
         diff_ref: "stage_artifact:diff:phase22",
         cost_ref: "cost:phase22",
         token_ref: "token:phase22",
         log_ref: "stage_artifact:runner_log:phase22"
       }},
      {DTO.StageArtifact, [:stage_artifact_ref, :kind, :digest, :bytes],
       %{
         stage_artifact_ref: "stage_artifact:phase22",
         kind: :diff,
         digest: "sha256:artifact",
         bytes: 128,
         stored_at_ref: "artifact_store:phase22"
       }}
    ]
  end

  defp at(seconds), do: DateTime.add(~U[2026-01-01 00:00:00Z], seconds, :second)
end
