defmodule Chassis.Policy.BoundaryTest do
  use ExUnit.Case, async: true

  alias Chassis.Boundary.{Envelope, Error}
  alias Chassis.Policy.{AuthorityAudit, Boundary, CliAuthority, WorkflowAuthority}
  alias Citadel.AuthorityContract.AuthorityDecision.V1, as: AuthorityDecisionV1
  alias Citadel.BoundaryIntent
  alias Citadel.TopologyIntent

  defmodule RaisingCompiler do
    def compile!(_decision, _boundary_intent, _topology_intent, _attrs) do
      raise "compiler unavailable"
    end
  end

  defmodule ForbiddenCompiler do
    def compile!(_decision, _boundary_intent, _topology_intent, _attrs) do
      raise "compiler must not run after authority failure"
    end
  end

  defmodule CapturingCompiler do
    def compile!(decision, boundary_intent, topology_intent, attrs) do
      send(self(), {:phase30_compiled, decision, boundary_intent, topology_intent, attrs})

      Citadel.ExecutionGovernanceCompiler.compile!(
        decision,
        boundary_intent,
        topology_intent,
        attrs
      )
    end
  end

  defmodule Provider do
    def authorize(request, _opts) do
      {:ok,
       Citadel.AuthorityContract.AuthorityDecision.V1.new!(%{
         contract_version: "v1",
         decision_id: "decision:" <> request["operation"],
         tenant_id: request["tenant_ref"],
         request_id: request["request_id"],
         policy_version: "policy:2026-06-02",
         boundary_class: request["authority_class"],
         trust_profile: "trusted_operator",
         approval_profile: "operator-and-policy",
         egress_profile: "outbound-controlled",
         workspace_profile: "chassis-deployment",
         resource_profile: "control-plane",
         decision_hash: String.duplicate("b", 64),
         extensions: %{"citadel" => %{}}
       })}
    end
  end

  defmodule DenyProvider do
    def authorize(_request, _opts), do: {:error, :authority_denied}
  end

  test "authorize/1 compiles a real Citadel execution governance packet and attaches authority_ref" do
    envelope = envelope(authority_ref: "authority:pending")
    decision = authority_decision(decision_id: "decision:phase13:deploy")

    assert {:ok, %Envelope{} = authorized} =
             Boundary.authorize(%{
               envelope: envelope,
               authority_decision: decision,
               operation: :materialize_deployment
             })

    assert authorized.authority_ref == "authority:decision:phase13:deploy"
    assert authorized.trace_id == envelope.trace_id

    assert %BoundaryIntent{} = Boundary.build_boundary_intent(envelope, :materialize_deployment)
    assert %TopologyIntent{} = Boundary.build_topology_intent(envelope)

    attrs = Boundary.build_attrs(envelope, :materialize_deployment, decision)
    assert attrs.execution_governance_id == decision.decision_id
    assert attrs.allowed_operations == ["materialize_deployment"]
    assert "ssh" in attrs.allowed_tools
  end

  test "fail-closed authority results return bounded boundary errors before compiler side effects" do
    for {reason, code, posture} <- [
          {:authority_denied, :authority_denied, :operator_required},
          {:authority_unavailable, :dependency_unavailable, :retryable},
          {:stale_revision, :stale_revision, :operator_required},
          {:timeout, :timeout, :retryable}
        ] do
      assert {:error, %Error{} = error} =
               Boundary.authorize(%{
                 envelope: envelope(authority_ref: "authority:pending"),
                 authority_result: {:error, reason},
                 operation: :materialize_deployment,
                 compiler: ForbiddenCompiler
               })

      assert error.code == code
      assert error.retry_posture == posture
      assert error.protocol_ref == "boundary:mezzanine.chassis.materialize_deployment:v1"
    end
  end

  test "compiler raises are converted to invalid_request errors" do
    assert {:error, %Error{} = error} =
             Boundary.authorize(%{
               envelope: envelope(authority_ref: "authority:pending"),
               authority_decision: authority_decision(),
               operation: :materialize_deployment,
               compiler: RaisingCompiler
             })

    assert error.code == :invalid_request
    assert error.safe_message =~ "authority compilation failed"
  end

  test "authorize_then/2 never executes chassis side effects unless authority succeeds" do
    test_pid = self()

    result =
      Boundary.authorize_then(
        %{
          envelope: envelope(authority_ref: "authority:pending"),
          authority_result: {:error, :authority_denied},
          operation: :materialize_deployment
        },
        fn _authorized ->
          send(test_pid, :side_effect_executed)
          {:ok, :side_effect}
        end
      )

    assert {:error, %Error{code: :authority_denied}} = result
    refute_received :side_effect_executed
  end

  test "CLI and workflow authority helpers acquire real AuthorityDecision packets through providers" do
    assert {:ok, %AuthorityDecisionV1{} = cli_decision} =
             CliAuthority.acquire(:materialize_deployment, authority_request_attrs(),
               provider: Provider
             )

    assert cli_decision.decision_id == "decision:materialize_deployment"
    assert cli_decision.tenant_id == "tenant:acme"
    assert cli_decision.boundary_class == "chassis.deploy"

    assert {:ok, %AuthorityDecisionV1{} = workflow_decision} =
             WorkflowAuthority.acquire(:drain_host, authority_request_attrs(), provider: Provider)

    assert workflow_decision.decision_id == "decision:drain_host"
    assert workflow_decision.boundary_class == "chassis.drain_host"

    assert {:error, %Error{code: :authority_denied}} =
             CliAuthority.acquire(:materialize_deployment, authority_request_attrs(),
               provider: DenyProvider
             )
  end

  test "authority_ref round-trips through envelope receipt attrs and effect log attrs" do
    {:ok, authorized} =
      Boundary.authorize(%{
        envelope: envelope(authority_ref: "authority:pending"),
        authority_decision: authority_decision(decision_id: "decision:round-trip"),
        operation: :materialize_deployment
      })

    assert {:ok, audit} =
             AuthorityAudit.round_trip(
               authorized,
               %{receipt_ref: "receipt:deploy:1", status: :ok},
               %{effect_ref: "effect:mezzanine:1", kind: :deployment_materialized}
             )

    assert audit.envelope.authority_ref == "authority:decision:round-trip"
    assert audit.receipt.authority_ref == audit.envelope.authority_ref
    assert audit.effect_log.authority_ref == audit.envelope.authority_ref
  end

  test "Phase 30 catalog exposes all Citadel evolution host model and hardware intents" do
    assert Boundary.authority_intents() == [
             "authority:chassis:evolution:create_batch",
             "authority:chassis:evolution:promote_candidate",
             "authority:chassis:evolution:provision_trial",
             "authority:chassis:evolution:request_promotion",
             "authority:chassis:evolution:rollback_candidate",
             "authority:chassis:evolution:run_coding_agent",
             "authority:chassis:evolution:score_candidate",
             "authority:chassis:evolution:start",
             "authority:chassis:hardware:admit_accelerator",
             "authority:chassis:host_daemon:rollback",
             "authority:chassis:host_daemon:swap",
             "authority:chassis:model:materialize_weight",
             "authority:chassis:model:reload_tensor_patch"
           ]

    for intent_ref <- Boundary.authority_intents() do
      assert {:ok, keys} = Boundary.binding_keys(intent_ref)
      assert :tenant_ref in keys
      assert :installation_ref in keys
      assert keys != []
    end
  end

  test "Phase 30 intent authorization compiles every binding key into the governance packet" do
    for intent_ref <- Boundary.authority_intents() do
      attrs = complete_intent_attrs(intent_ref)

      request =
        base_intent_request(intent_ref)
        |> Map.put(:attrs, attrs)
        |> maybe_put_consent(attrs)

      assert {:ok, result} =
               Boundary.authorize_intent(request,
                 compiler: CapturingCompiler,
                 now: ~U[2026-06-03 10:45:00Z]
               )

      assert result.authority_ref =~ "authority:decision:"

      assert_received {:phase30_compiled, _decision, boundary_intent, _topology_intent,
                       compiled_attrs}

      assert boundary_intent.boundary_class =~ "chassis"
      assert compiled_attrs.extensions["citadel"]["chassis"]["intent_ref"] == intent_ref

      assert {:ok, binding_keys} = Boundary.binding_keys(intent_ref)

      for key <- binding_keys do
        assert Map.has_key?(result.binding_attrs, key)

        assert Map.has_key?(
                 compiled_attrs.extensions["citadel"]["chassis"]["bindings"],
                 Atom.to_string(key)
               )
      end
    end
  end

  test "Phase 30 promote candidate fails closed without operator consent ref" do
    intent_ref = "authority:chassis:evolution:promote_candidate"
    attrs = complete_intent_attrs(intent_ref) |> Map.delete(:operator_consent_ref)

    assert {:error, %Error{} = error} =
             intent_ref
             |> base_intent_request()
             |> Map.put(:attrs, attrs)
             |> Boundary.authorize_intent()

    assert error.code == :authority_denied
    assert error.safe_message =~ "operator_consent_ref"
  end

  test "Phase 30 promote candidate fails closed when consent is expired" do
    intent_ref = "authority:chassis:evolution:promote_candidate"
    attrs = complete_intent_attrs(intent_ref)

    request =
      Map.merge(base_intent_request(intent_ref), %{
        attrs: attrs,
        operator_consent: %{consent_record(attrs) | recorded_at: ~U[2026-06-03 09:00:00Z]}
      })

    assert {:error, %Error{} = error} =
             Boundary.authorize_intent(request,
               now: ~U[2026-06-03 11:00:01Z],
               consent_ttl_seconds: 3600
             )

    assert error.code == :authority_denied
    assert error.safe_message =~ "expired"
  end

  test "Phase 30 mutation guard requires authority and distinct consent for swaps" do
    assert {:error, %Error{code: :authority_denied, safe_message: message}} =
             Boundary.assert_mutation_authorized(%{
               intent_ref: "authority:chassis:evolution:rollback_candidate",
               authority_ref: nil
             })

    assert message =~ "authority_ref"

    assert {:error, %Error{code: :authority_denied, safe_message: message}} =
             Boundary.assert_mutation_authorized(%{
               intent_ref: "authority:chassis:host_daemon:swap",
               authority_ref: "authority:decision:1",
               operator_consent_ref: "authority:decision:1"
             })

    assert message =~ "distinct"

    assert :ok =
             Boundary.assert_mutation_authorized(%{
               intent_ref: "authority:chassis:host_daemon:swap",
               authority_ref: "authority:decision:1",
               operator_consent_ref: "operator-consent:1"
             })
  end

  defp envelope(overrides) do
    %{
      protocol_ref: "boundary:mezzanine.chassis.materialize_deployment:v1",
      envelope_ref: "env:policy:1",
      tenant_ref: "tenant:acme",
      installation_ref: "installation:local",
      actor_ref: "user:operator",
      system_actor_ref: "system:chassis",
      authority_ref: "authority:old",
      idempotency_key: "policy:1",
      trace_id: "trace:policy:1",
      correlation_id: "corr:policy:1",
      issued_at: ~U[2026-06-02 10:00:00Z],
      status: :request,
      payload: %Chassis.Boundary.MaterializeDeployment.Request{
        topology_ref: "topology:alpha",
        service_spec_ref: "service:web",
        environment: :dev,
        git_sha: "abcdef123456",
        release_version: "2026.06.02"
      }
    }
    |> Map.merge(Map.new(overrides))
    |> Envelope.new!()
  end

  defp authority_decision(opts \\ []) do
    AuthorityDecisionV1.new!(%{
      contract_version: "v1",
      decision_id: Keyword.get(opts, :decision_id, "decision:phase13:1"),
      tenant_id: Keyword.get(opts, :tenant_id, "tenant:acme"),
      request_id: Keyword.get(opts, :request_id, "req:phase13:1"),
      policy_version: Keyword.get(opts, :policy_version, "policy:2026-06-02"),
      boundary_class: Keyword.get(opts, :boundary_class, "chassis.deploy"),
      trust_profile: "trusted_operator",
      approval_profile: "operator-and-policy",
      egress_profile: "outbound-controlled",
      workspace_profile: "chassis-deployment",
      resource_profile: "control-plane",
      decision_hash: String.duplicate("a", 64),
      extensions: %{"citadel" => %{}}
    })
  end

  defp authority_request_attrs do
    %{
      actor_ref: "user:operator",
      tenant_ref: "tenant:acme",
      installation_ref: "installation:local",
      request_id: "req:helper:1",
      trace_id: "trace:helper:1"
    }
  end

  defp base_intent_request(intent_ref) do
    %{
      intent_ref: intent_ref,
      tenant_ref: "tenant:acme",
      installation_ref: "installation:prod",
      trace_id: "trace:phase30:intent"
    }
  end

  defp consent_record(attrs) do
    %{
      operator_consent_ref: Map.fetch!(attrs, :operator_consent_ref),
      candidate_ref: Map.fetch!(attrs, :candidate_ref),
      decision: :approve,
      recorded_at: ~U[2026-06-03 10:30:00Z],
      actor_ref: "user:operator"
    }
  end

  defp complete_intent_attrs(intent_ref) do
    common = %{
      tenant_ref: "tenant:acme",
      installation_ref: "installation:prod",
      candidate_ref: "cand:phase30",
      failure_batch_ref: "failure-batch:phase30",
      patch_digest: "sha256:patch-phase30",
      base_release_ref: "release:base:phase30",
      artifact_digest: "sha256:artifact-phase30",
      score_matrix_ref: "score-matrix:phase30",
      target_installation_ref: "installation:prod",
      approved_state_volume_mounts: ["/srv/chassis/state"],
      rollback_ref: "rollback:phase30",
      operator_consent_ref: "operator-consent:phase30",
      trace_id: "trace:phase30:intent",
      redaction_posture: :default,
      evidence_refs: ["evidence:one", "evidence:two"],
      runner_profile_ref: "runner-profile:phase30",
      scorer_profile_ref: "scorer-profile:phase30",
      trial_profile_ref: "trial-profile:phase30",
      budget_ref: "budget:phase30",
      runner_kind: :codex,
      trial_runtime_kind: :container,
      trial_run_ref: "trial-run:phase30",
      swap_ref: "swap:phase30",
      reason_code: :health_probe_failed,
      host_target_ref: "host:prod:1",
      host_swap_strategy: :blue_green,
      model_ref: "model:phase30",
      target_host_ref: "host:gpu:1",
      source_strategy: :hf_hub,
      expected_digest_ref: "sha256:weight-phase30",
      bandwidth_class: :standard,
      cache_root_ref: "cache-root:model",
      patch_ref: "tensor-patch:phase30",
      target_runtime_ref: "runtime:phase30",
      reload_strategy: :in_place,
      rollback_patch_ref: "tensor-patch:rollback",
      host_ref: "host:gpu:1",
      runtime_ref: "runtime:phase30",
      required_capabilities: %{gpu: %{vendor: "nvidia", memory_gb: 24}}
    }

    {:ok, keys} = Boundary.binding_keys(intent_ref)
    common |> Boundary.build_binding_attrs!(keys)
  end

  defp maybe_put_consent(
         %{intent_ref: "authority:chassis:evolution:promote_candidate"} = request,
         attrs
       ) do
    Map.put(request, :operator_consent, consent_record(attrs))
  end

  defp maybe_put_consent(request, _attrs), do: request
end
