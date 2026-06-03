defmodule Chassis.Evolution.ConformanceTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Chassis.Evolution.Conformance
  alias Chassis.Evolution.Conformance.Asserts
  alias Chassis.Evolution.Conformance.Runner

  @scenarios [
    :source_level_patch_success,
    :forced_probe_rollback,
    :authority_denied,
    :consent_missing,
    :trial_regression_blocked,
    :coding_agent_crash,
    :candidate_build_failure,
    :health_probe_timeout,
    :state_volume_missing,
    :forbidden_production_state_in_trial,
    :appkit_raw_diff_blocked,
    :receipt_redaction_check
  ]

  test "source_level_patch_success drives all lifecycle evidence surfaces" do
    tmp = tmp_dir()

    assert {:ok, report} =
             Conformance.run(:source_level_patch_success,
               receipts_dir: tmp,
               trace_id: "trace:phase36:source"
             )

    assert report.scenario == :source_level_patch_success
    assert report.final_state == :committed
    assert report.citadel.decision == :allow
    assert report.operator_consent.decision == :approve
    assert report.appkit.status.state == :committed
    assert report.appkit.candidate_summary.redacted_diff_ref.diff_ref =~ "diff:"
    refute Map.has_key?(report.appkit.candidate_summary, :raw_diff)

    assert length(report.lifecycle_steps) == 16
    assert length(report.spans) == 16
    assert length(report.metrics) == 16
    assert length(report.receipts) == 16
    assert length(report.projections) == 16
    assert Enum.all?(report.spans, &(&1.trace_id == "trace:phase36:source"))
    assert Enum.all?(report.metrics, &(&1.name =~ "chassis_evolution_"))

    assert :ok = Asserts.final_state(report, :committed)
    assert :ok = Asserts.span_emitted(report, "chassis.evolution.committed")
    assert :ok = Asserts.metric_incremented(report, "chassis_evolution_committed_total")
    assert :ok = Asserts.receipt_present(report, :promotion)
    assert :ok = Asserts.no_raw_secrets_in(tmp)
  end

  test "negative scenarios block unsafe side effects and emit terminal evidence" do
    assert {:ok, denied} = Conformance.run(:authority_denied)
    assert denied.final_state == :stopped
    assert denied.citadel.decision == :deny
    assert denied.swap.enqueued? == false
    assert denied.host_daemon_calls == []
    assert :ok = Asserts.receipt_present(denied, :boundary_decision)

    assert {:ok, missing} = Conformance.run(:consent_missing)
    assert missing.final_state == :stopped
    assert missing.swap.enqueued? == false
    assert :promotion_blocked_consent in missing.appkit.status.operator_action_hints

    assert {:ok, trial_blocked} = Conformance.run(:forbidden_production_state_in_trial)
    assert trial_blocked.final_state == :failed
    assert trial_blocked.trial.outcome == :forbidden_mount
    assert trial_blocked.host_daemon_calls == []
    assert :ok = Asserts.no_production_state_in_trial(trial_blocked.trial)
  end

  test "receipt redaction scenario writes no raw secrets to receipts or projections" do
    tmp = tmp_dir()
    secret = "BEGIN PRIVATE KEY phase36 api_key=password"

    assert {:ok, report} =
             Conformance.run(:receipt_redaction_check,
               receipts_dir: tmp,
               injected_secret: secret
             )

    assert report.final_state == :passed
    assert :ok = Asserts.no_raw_secrets_in(tmp)
    refute inspect(report.receipts) =~ "BEGIN PRIVATE KEY"
    refute inspect(report.spans) =~ "api_key"
    refute inspect(report.projections) =~ "password"
  end

  test "runner executes all twelve scenarios and records invariant proofs" do
    assert @scenarios == Conformance.scenarios()
    assert {:ok, report} = Runner.run_all()

    assert report.passed == 12
    assert report.failed == 0
    assert Enum.map(report.scenarios, & &1.scenario) == @scenarios
    assert Enum.all?(report.scenarios, &(is_list(&1.spans) and is_list(&1.metrics)))
    assert report.invariants.no_raw_secrets_in_receipts == :pass
    assert report.invariants.mezzanine_projections_reduced == :pass
  end

  test "test emitters capture span and metric DTOs without raw payloads" do
    Chassis.AITrace.Bridge.TestEmitter.reset()
    Chassis.Metrics.Backend.Test.reset()

    assert {:ok, _report} =
             Conformance.run(:forced_probe_rollback,
               trace_id: "trace:phase36:emitters",
               aitrace_emitter: Chassis.AITrace.Bridge.TestEmitter,
               metrics_backend: Chassis.Metrics.Backend.Test
             )

    spans = Chassis.AITrace.Bridge.TestEmitter.list()
    metrics = Chassis.Metrics.Backend.Test.list()

    assert Enum.any?(spans, &(&1.name == "chassis.evolution.rolled_back"))
    assert Enum.all?(spans, &(&1.trace_id == "trace:phase36:emitters"))
    assert Enum.any?(metrics, &(&1.name == "chassis_evolution_rolled_back_total"))
    refute inspect(spans) =~ "BEGIN PRIVATE KEY"
    refute inspect(metrics) =~ "api_key"
  end

  test "fixture and proof Mix tasks emit JSON derived from scenario execution" do
    Mix.Task.reenable("chassis.evolution.fixture")
    Mix.Task.reenable("chassis.evolution.proof")

    fixture =
      capture_io(fn ->
        Mix.Tasks.Chassis.Evolution.Fixture.run([
          "--scenario",
          "source_level_patch_success",
          "--json"
        ])
      end)

    assert {:ok, fixture_json} = Jason.decode(fixture)
    assert fixture_json["scenario"] == "source_level_patch_success"
    assert fixture_json["final_state"] == "committed"
    assert length(fixture_json["spans"]) == 16

    proof =
      capture_io(fn ->
        Mix.Tasks.Chassis.Evolution.Proof.run([
          "--app",
          "extravaganza",
          "--profile",
          "profile:ternary-split-3",
          "--env",
          "prod",
          "--fixture",
          "fixture:source_level_repair_001",
          "--require-trial",
          "--require-citadel-consent",
          "--require-health-gated-swap",
          "--require-rollback-proof",
          "--json"
        ])
      end)

    assert {:ok, proof_json} = Jason.decode(proof)
    assert proof_json["passed"] == 12
    assert proof_json["failed"] == 0
    assert proof_json["requirements"]["trial"] == true
    assert proof_json["requirements"]["rollback_proof"] == true
  end

  defp tmp_dir do
    path = Path.join(System.tmp_dir!(), "chassis_phase36_#{System.unique_integer([:positive])}")
    File.rm_rf!(path)
    File.mkdir_p!(path)
    on_exit(fn -> File.rm_rf(path) end)
    path
  end
end
