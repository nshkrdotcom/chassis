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
end
