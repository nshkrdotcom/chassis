defmodule Chassis.Boundary.AdapterTest do
  use ExUnit.Case, async: true

  alias Chassis.Boundary.{BeamDistributionAdapter, Envelope, Error, LocalAdapter, Protocol}

  defmodule EchoProtocol do
    @behaviour Protocol

    @impl true
    def call(%Envelope{} = envelope, _opts) do
      {:ok,
       Envelope.response!(envelope, %Chassis.Boundary.MaterializeDeployment.Response{
         deployment_receipt_ref: "receipt:" <> envelope.envelope_ref,
         app_ref: "app:" <> envelope.tenant_ref,
         node_mesh: [:chassis_local],
         status: :ok,
         duration_ms: 12
       })}
    end
  end

  defmodule RaisingProtocol do
    @behaviour Protocol

    @impl true
    def call(_envelope, _opts), do: raise("boom")
  end

  test "local adapter invokes the registered protocol module and returns a response envelope" do
    envelope = envelope()

    assert {:ok, %Envelope{} = response} =
             LocalAdapter.dispatch(envelope, protocol_module: EchoProtocol)

    assert response.protocol_ref == envelope.protocol_ref
    assert response.correlation_id == envelope.correlation_id
    assert response.trace_id == envelope.trace_id
    assert response.status == :ok
    assert response.payload.deployment_receipt_ref == "receipt:" <> envelope.envelope_ref
    assert response.receipt_refs == ["receipt:" <> envelope.envelope_ref]
  end

  test "dispatcher chooses local or BEAM adapters from target_node option" do
    envelope = envelope()

    assert {:ok, local_response} =
             Chassis.Boundary.dispatch(envelope,
               protocol_module: EchoProtocol,
               target_node: :local
             )

    assert {:ok, beam_response} =
             Chassis.Boundary.dispatch(envelope,
               protocol_module: EchoProtocol,
               target_node: Node.self()
             )

    assert Envelope.digest(local_response) == Envelope.digest(beam_response)
  end

  test "beam remote dispatch decodes with the GroundPlane codec before local dispatch" do
    envelope = envelope()
    encoded = Envelope.encode!(envelope)

    assert {:ok, response} =
             BeamDistributionAdapter.__remote_dispatch__(encoded, protocol_module: EchoProtocol)

    assert %Chassis.Boundary.MaterializeDeployment.Response{} = response.payload
    assert response.status == :ok
  end

  test "adapter failures return bounded boundary errors" do
    assert {:error, %Error{} = error} =
             LocalAdapter.dispatch(envelope(), protocol_module: RaisingProtocol)

    assert error.code == :non_retryable_failure
    assert error.retry_posture == :non_retryable
    assert error.safe_message == "Local adapter raised an exception"
    assert error.redaction == :safe
  end

  defp envelope do
    Envelope.new!(%{
      protocol_ref: "boundary:mezzanine.chassis.materialize_deployment:v1",
      envelope_ref: "env:adapter:1",
      tenant_ref: "tenant:acme",
      installation_ref: "installation:local",
      actor_ref: "user:operator",
      system_actor_ref: "system:chassis",
      authority_ref: "authority:citadel:snapshot:1",
      idempotency_key: "adapter:1",
      trace_id: "trace:adapter:1",
      correlation_id: "corr:adapter:1",
      issued_at: ~U[2026-06-02 10:00:00Z],
      status: :request,
      payload: %Chassis.Boundary.MaterializeDeployment.Request{
        topology_ref: "topology:alpha",
        service_spec_ref: "service:web",
        environment: :dev,
        git_sha: "abcdef123456",
        release_version: "2026.06.02"
      }
    })
  end
end
