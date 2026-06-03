defmodule Chassis.Boundary.EnvelopeTest do
  use ExUnit.Case, async: true

  alias Chassis.Boundary.Envelope
  alias Chassis.Secrets.{SecretLease, SecretRef}

  @materialize_ref "boundary:mezzanine.chassis.materialize_deployment:v1"

  test "new!/1 builds the canonical envelope and GroundPlane codec digest is stable" do
    envelope =
      Envelope.new!(%{
        protocol_ref: @materialize_ref,
        envelope_ref: "env:boundary:1",
        tenant_ref: "tenant:acme",
        installation_ref: "installation:local",
        actor_ref: "user:operator",
        system_actor_ref: "system:chassis",
        authority_ref: "authority:citadel:snapshot:1",
        idempotency_key: "deploy:2026-06-02:1",
        trace_id: "trace:phase12:stable",
        correlation_id: "corr:phase12:stable",
        issued_at: ~U[2026-06-02 10:00:00Z],
        status: :request,
        payload: %Chassis.Boundary.MaterializeDeployment.Request{
          topology_ref: "topology:alpha",
          service_spec_ref: "service:web",
          runtime_profile_ref: "runtime:monolith",
          placement_ref: "placement:local",
          environment: :dev,
          git_sha: "abcdef123456",
          release_version: "2026.06.02"
        }
      })

    assert %Envelope{receipt_refs: []} = envelope
    encoded_once = Envelope.encode!(envelope)
    encoded_twice = Envelope.encode!(envelope)

    assert encoded_once == encoded_twice
    assert Envelope.decode!(encoded_once)["payload"]["environment"] == "dev"

    assert Envelope.digest(envelope) ==
             Envelope.digest(Envelope.new!(Envelope.decode!(encoded_once)))
  end

  test "mutating envelopes fail closed without tenant authority trace and idempotency context" do
    for field <- [:tenant_ref, :authority_ref, :idempotency_key, :trace_id, :envelope_ref] do
      attrs = Map.delete(base_mutating_attrs(), field)

      assert_raise ArgumentError, ~r/#{field}/, fn ->
        Envelope.new!(attrs)
      end
    end
  end

  test "encoding rejects raw credentials keys pids unsafe atoms secret leases and key bytes" do
    for {payload, reason} <- [
          {%{"password" => "not-for-boundary"}, "raw_credential_key_forbidden"},
          {%{pid: self()}, "boundary_pid_not_serializable"},
          {%{system_atom: :erlang}, "unsafe_atom"},
          {%{lease: secret_lease()}, "SecretLease"},
          {%{public_label: pem_private_key()}, "raw private key"}
        ] do
      envelope = Envelope.new!(Map.put(base_mutating_attrs(), :payload, payload))

      assert_raise ArgumentError, ~r/#{reason}/, fn ->
        Envelope.encode!(envelope)
      end
    end
  end

  defp base_mutating_attrs do
    %{
      protocol_ref: @materialize_ref,
      envelope_ref: "env:boundary:validation",
      tenant_ref: "tenant:acme",
      authority_ref: "authority:citadel:snapshot:1",
      idempotency_key: "deploy:validation",
      trace_id: "trace:validation",
      status: :request,
      issued_at: ~U[2026-06-02 10:00:00Z],
      payload: %{topology_ref: "topology:alpha"}
    }
  end

  defp secret_lease do
    ref =
      SecretRef.new!(%{
        secret_ref: "secret:db-password",
        tenant_ref: "tenant:acme",
        backend: :env,
        key: "DB_PASSWORD"
      })

    SecretLease.new!(ref, "super-secret", consumer_ref: "boundary-test")
  end

  defp pem_private_key do
    """
    -----BEGIN OPENSSH PRIVATE KEY-----
    b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAA=
    -----END OPENSSH PRIVATE KEY-----
    """
  end
end
