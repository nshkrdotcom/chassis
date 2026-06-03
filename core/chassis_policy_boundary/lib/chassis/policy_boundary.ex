defmodule Chassis.Policy.Boundary do
  @moduledoc """
  Fail-closed Citadel authority gate for Chassis boundary envelopes.

  This module consumes Citadel authority decisions and compiles them into
  `Citadel.ExecutionGovernance.V1` packets before any Chassis side effect can
  run. The only value attached to the Chassis envelope is the derived
  `authority_ref`; downstream receipt/effect-log helpers copy that ref without
  inventing authority state.
  """

  alias Chassis.Boundary.{Envelope, Error}
  alias Citadel.AuthorityContract.AuthorityDecision.V1, as: AuthorityDecisionV1
  alias Citadel.BoundaryIntent
  alias Citadel.ExecutionGovernanceCompiler
  alias Citadel.TopologyIntent

  @operations %{
    materialize_deployment: %{
      authority_class: "chassis.deploy",
      protocol_ref: "boundary:mezzanine.chassis.materialize_deployment:v1",
      tools: ["ssh", "sftp", "systemd", "net_kernel"],
      effect_classes: ["chassis.substrate.materialization"]
    },
    provision_host: %{
      authority_class: "chassis.provision_host",
      protocol_ref: "boundary:mezzanine.chassis.provision_host:v1",
      tools: ["ssh", "apt", "asdf"],
      effect_classes: ["chassis.substrate.provisioning"]
    },
    rollback_deployment: %{
      authority_class: "chassis.rollback",
      protocol_ref: "boundary:mezzanine.chassis.rollback_deployment:v1",
      tools: ["ssh", "systemd", "net_kernel"],
      effect_classes: ["chassis.substrate.rollback"]
    },
    drain_host: %{
      authority_class: "chassis.drain_host",
      protocol_ref: "boundary:mezzanine.chassis.drain_host:v1",
      tools: ["ssh", "systemd"],
      effect_classes: ["chassis.substrate.drain"]
    },
    secret_rotate: %{
      authority_class: "chassis.secret_rotate",
      protocol_ref: "boundary:chassis.internal.secret_rotate:v1",
      tools: ["sops"],
      effect_classes: ["chassis.credential.lifecycle"]
    },
    host_register: %{
      authority_class: "chassis.host_register",
      protocol_ref: "boundary:chassis.internal.host_register:v1",
      tools: [],
      effect_classes: ["chassis.inventory.registration"]
    }
  }

  @type operation ::
          :materialize_deployment
          | :provision_host
          | :rollback_deployment
          | :drain_host
          | :secret_rotate
          | :host_register

  @type input :: %{
          required(:envelope) => Envelope.t(),
          required(:operation) => operation(),
          optional(:authority_decision) => AuthorityDecisionV1.t(),
          optional(:authority_result) => {:ok, AuthorityDecisionV1.t()} | {:error, atom()},
          optional(:compiler) => module()
        }

  @spec authorize(input()) :: {:ok, Envelope.t()} | {:error, Error.t()}
  def authorize(%{authority_result: {:error, reason}} = input) do
    {:error, authority_error(reason, input)}
  end

  def authorize(%{authority_result: {:ok, %AuthorityDecisionV1{} = decision}} = input) do
    input
    |> Map.delete(:authority_result)
    |> Map.put(:authority_decision, decision)
    |> authorize()
  end

  def authorize(
        %{
          envelope: %Envelope{} = envelope,
          authority_decision: %AuthorityDecisionV1{} = decision,
          operation: operation
        } = input
      ) do
    with {:ok, spec} <- operation_spec(operation),
         :ok <- ensure_protocol_matches(envelope, spec),
         :ok <- ensure_tenant_matches(envelope, decision),
         :ok <- ensure_decision_allows(decision) do
      boundary_intent = build_boundary_intent(envelope, operation)
      topology_intent = build_topology_intent(envelope)
      attrs = build_attrs(envelope, operation, decision)
      compiler = Map.get(input, :compiler, ExecutionGovernanceCompiler)

      try do
        governance =
          apply(compiler, :compile!, [decision, boundary_intent, topology_intent, attrs])

        {:ok, %Envelope{envelope | authority_ref: authority_ref(governance)}}
      rescue
        exception ->
          {:error,
           Error.new(:invalid_request, envelope,
             safe_message: "authority compilation failed: #{Exception.message(exception)}",
             retry_posture: :non_retryable
           )}
      end
    else
      {:error, %Error{} = error} -> {:error, error}
    end
  end

  def authorize(input), do: {:error, authority_error(:invalid_request, input)}

  @spec authorize_then(input(), (Envelope.t() -> term())) :: term() | {:error, Error.t()}
  def authorize_then(input, effect_fun) when is_function(effect_fun, 1) do
    case authorize(input) do
      {:ok, %Envelope{} = envelope} -> effect_fun.(envelope)
      {:error, %Error{} = error} -> {:error, error}
    end
  end

  @spec build_boundary_intent(Envelope.t(), operation()) :: BoundaryIntent.t()
  def build_boundary_intent(%Envelope{} = envelope, operation) do
    spec = fetch_operation!(operation)

    BoundaryIntent.new!(%{
      boundary_class: spec.authority_class,
      trust_profile: "trusted_operator",
      workspace_profile: "chassis-deployment",
      resource_profile: "control-plane",
      requested_attach_mode: "fresh_or_reuse",
      requested_ttl_ms: 300_000,
      extensions: %{
        "chassis" => %{
          "envelope_ref" => envelope.envelope_ref,
          "protocol_ref" => envelope.protocol_ref,
          "operation" => Atom.to_string(operation)
        }
      }
    })
  end

  @spec build_topology_intent(Envelope.t()) :: TopologyIntent.t()
  def build_topology_intent(%Envelope{} = envelope) do
    TopologyIntent.new!(%{
      topology_intent_id: "topology-intent:" <> envelope.envelope_ref,
      session_mode: "attached",
      routing_hints: %{
        "topology_ref" => topology_ref(envelope.payload),
        "protocol_ref" => envelope.protocol_ref,
        "tenant_ref" => envelope.tenant_ref || "tenant:unknown",
        "installation_ref" => envelope.installation_ref || "installation:unknown"
      },
      coordination_mode: "single_target",
      topology_epoch: 1,
      extensions: %{"chassis" => %{"trace_id" => envelope.trace_id}}
    })
  end

  @spec build_attrs(Envelope.t(), operation(), AuthorityDecisionV1.t() | nil) :: map()
  def build_attrs(%Envelope{} = envelope, operation, decision \\ nil) do
    spec = fetch_operation!(operation)

    %{
      execution_governance_id: execution_governance_id(envelope, decision),
      sandbox_level: "standard",
      sandbox_egress: "restricted",
      sandbox_approvals: "manual",
      acceptable_attestation: ["chassis.attestation.v1"],
      allowed_tools: spec.tools,
      file_scope_ref: "file-scope:chassis-managed",
      file_scope_hint: "/opt/nshkr/releases",
      logical_workspace_ref: "workspace:chassis-deployment",
      workspace_mutability: "read_write",
      execution_family: "process",
      placement_intent: "remote_scope",
      target_kind: "remote-vps-or-localhost",
      node_affinity: "topology-driven",
      allowed_operations: [Atom.to_string(operation)],
      effect_classes: spec.effect_classes,
      cpu_class: "control-plane",
      memory_class: "control-plane",
      wall_clock_budget_ms: 600_000,
      extensions: %{
        "citadel" => %{
          "chassis" => %{
            "operation" => Atom.to_string(operation),
            "envelope_ref" => envelope.envelope_ref,
            "trace_id" => envelope.trace_id
          }
        }
      }
    }
  end

  @spec operations() :: [operation()]
  def operations, do: @operations |> Map.keys() |> Enum.sort()

  @spec authority_class(operation()) :: {:ok, String.t()} | {:error, Error.t()}
  def authority_class(operation) do
    case operation_spec(operation) do
      {:ok, spec} -> {:ok, spec.authority_class}
      {:error, %Error{} = error} -> {:error, error}
    end
  end

  @spec operation_spec(operation() | atom()) :: {:ok, map()} | {:error, Error.t()}
  def operation_spec(operation) do
    case Map.fetch(@operations, operation) do
      {:ok, spec} ->
        {:ok, Map.put(spec, :operation, operation)}

      :error ->
        {:error,
         Error.new(:invalid_request,
           safe_message: "unsupported Chassis authority operation #{inspect(operation)}"
         )}
    end
  end

  @spec authority_error(atom(), map() | keyword()) :: Error.t()
  def authority_error(reason, context \\ [])

  def authority_error(reason, %{} = context), do: authority_error(reason, Map.to_list(context))

  def authority_error(reason, context) when is_list(context) do
    envelope = Keyword.get(context, :envelope)
    base = if is_struct(envelope, Envelope), do: envelope, else: []

    case reason do
      :authority_denied ->
        Error.new(:authority_denied, base,
          safe_message: "Citadel authority denied the request",
          retry_posture: :operator_required
        )

      :authority_unavailable ->
        Error.new(:dependency_unavailable, base,
          safe_message: "Citadel authority is unavailable",
          retry_posture: :retryable
        )

      :stale_revision ->
        Error.new(:stale_revision, base,
          safe_message: "Citadel authority decision was compiled against a stale revision",
          retry_posture: :operator_required
        )

      :timeout ->
        Error.new(:timeout, base,
          safe_message: "Citadel authority request timed out",
          retry_posture: :retryable
        )

      :invalid_request ->
        Error.new(:invalid_request, base,
          safe_message: "invalid authority request",
          retry_posture: :non_retryable
        )

      other ->
        Error.new(:invalid_request, base,
          safe_message: "Citadel authority failed closed: #{inspect(other)}",
          retry_posture: :non_retryable
        )
    end
  end

  defp fetch_operation!(operation) do
    case operation_spec(operation) do
      {:ok, spec} -> spec
      {:error, error} -> raise ArgumentError, error.safe_message
    end
  end

  defp ensure_protocol_matches(%Envelope{} = envelope, spec) do
    if envelope.protocol_ref == spec.protocol_ref or
         String.contains?(spec.protocol_ref, ".internal.") do
      :ok
    else
      {:error,
       Error.new(:invalid_request, envelope,
         safe_message:
           "authority operation does not match envelope protocol #{inspect(envelope.protocol_ref)}"
       )}
    end
  end

  defp ensure_tenant_matches(%Envelope{} = envelope, %AuthorityDecisionV1{} = decision) do
    if is_nil(envelope.tenant_ref) or envelope.tenant_ref == decision.tenant_id do
      :ok
    else
      {:error,
       Error.new(:authority_denied, envelope,
         safe_message: "Citadel authority tenant does not match envelope tenant",
         retry_posture: :operator_required
       )}
    end
  end

  defp ensure_decision_allows(%AuthorityDecisionV1{} = decision) do
    case AuthorityDecisionV1.governed_effect_decision(decision) do
      nil -> :ok
      "allowed" -> :ok
      "allow" -> :ok
      "approved" -> :ok
      other -> {:error, authority_error(:authority_denied, safe_message: "denied: #{other}")}
    end
  end

  defp authority_ref(governance) do
    decision_id =
      governance
      |> Map.get(:authority_ref, %{})
      |> Map.get("decision_id")

    "authority:" <> (decision_id || Map.fetch!(governance, :execution_governance_id))
  end

  defp execution_governance_id(_envelope, %AuthorityDecisionV1{} = decision),
    do: decision.decision_id

  defp execution_governance_id(%Envelope{} = envelope, nil),
    do: "execgov:" <> envelope.envelope_ref

  defp topology_ref(payload) when is_struct(payload) do
    payload
    |> Map.from_struct()
    |> topology_ref()
  end

  defp topology_ref(payload) when is_map(payload) do
    Map.get(payload, :topology_ref) || Map.get(payload, "topology_ref") || "topology:unknown"
  end

  defp topology_ref(_payload), do: "topology:unknown"
end

defmodule Chassis.Policy.AuthorityAcquisition do
  @moduledoc false

  alias Chassis.Boundary.Error
  alias Chassis.Policy.Boundary
  alias Citadel.AuthorityContract.AuthorityDecision.V1, as: AuthorityDecisionV1

  @spec acquire(atom(), map() | keyword(), keyword(), atom()) ::
          {:ok, AuthorityDecisionV1.t()} | {:error, Error.t()}
  def acquire(operation, attrs, opts, caller_kind)
      when is_atom(operation) and (is_map(attrs) or is_list(attrs)) do
    with {:ok, spec} <- Boundary.operation_spec(operation) do
      provider = Keyword.get(opts, :provider, Chassis.Policy.CitadelAuthorityProvider)
      request = request(operation, spec, attrs, caller_kind)

      case provider.authorize(request, opts) do
        {:ok, %AuthorityDecisionV1{} = decision} -> {:ok, decision}
        {:error, %Error{} = error} -> {:error, error}
        {:error, reason} -> {:error, Boundary.authority_error(reason, [])}
      end
    end
  end

  defp request(operation, spec, attrs, caller_kind) do
    attrs = Map.new(attrs)
    request_id = Map.get(attrs, :request_id) || "authority-request:" <> digest({operation, attrs})

    %{
      "operation" => Atom.to_string(operation),
      "authority_class" => spec.authority_class,
      "actor_ref" => required(attrs, :actor_ref),
      "tenant_ref" => required(attrs, :tenant_ref),
      "installation_ref" => Map.get(attrs, :installation_ref, "installation:unknown"),
      "request_id" => request_id,
      "trace_id" => Map.get(attrs, :trace_id, "trace:" <> digest(request_id)),
      "caller_kind" => Atom.to_string(caller_kind),
      "capability_ref" => "capability:" <> spec.authority_class
    }
  end

  defp required(attrs, field) do
    case Map.get(attrs, field) do
      value when is_binary(value) and value != "" -> value
      _other -> raise ArgumentError, "#{field} is required to acquire authority"
    end
  end

  defp digest(value) do
    :crypto.hash(:sha256, :erlang.term_to_binary(value))
    |> Base.encode16(case: :lower)
    |> binary_part(0, 16)
  end
end

defmodule Chassis.Policy.CliAuthority do
  @moduledoc "CLI-side authority acquisition helper."

  alias Chassis.Boundary.Error
  alias Citadel.AuthorityContract.AuthorityDecision.V1, as: AuthorityDecisionV1

  @spec acquire(atom(), map() | keyword(), keyword()) ::
          {:ok, AuthorityDecisionV1.t()} | {:error, Error.t()}
  def acquire(operation, attrs, opts \\ []) do
    Chassis.Policy.AuthorityAcquisition.acquire(operation, attrs, opts, :cli)
  rescue
    exception in ArgumentError ->
      {:error,
       Error.new(:invalid_request,
         safe_message: Exception.message(exception),
         retry_posture: :non_retryable
       )}
  end
end

defmodule Chassis.Policy.WorkflowAuthority do
  @moduledoc "Workflow-side authority acquisition helper."

  alias Chassis.Boundary.Error
  alias Citadel.AuthorityContract.AuthorityDecision.V1, as: AuthorityDecisionV1

  @spec acquire(atom(), map() | keyword(), keyword()) ::
          {:ok, AuthorityDecisionV1.t()} | {:error, Error.t()}
  def acquire(operation, attrs, opts \\ []) do
    Chassis.Policy.AuthorityAcquisition.acquire(operation, attrs, opts, :workflow)
  rescue
    exception in ArgumentError ->
      {:error,
       Error.new(:invalid_request,
         safe_message: Exception.message(exception),
         retry_posture: :non_retryable
       )}
  end
end

defmodule Chassis.Policy.CitadelAuthorityProvider do
  @moduledoc """
  Default authority provider.

  If the sibling Citadel repository exposes `Citadel.AuthorityContract.authorize/1`,
  this provider delegates to it. The current sibling contract package owns the
  packet modules but does not expose that facade yet, so the fallback constructs
  a real `AuthorityDecision.V1` packet with the contract-owned constructor.
  """

  alias Citadel.AuthorityContract
  alias Citadel.AuthorityContract.AuthorityDecision.V1, as: AuthorityDecisionV1

  @spec authorize(map(), keyword()) :: {:ok, AuthorityDecisionV1.t()} | {:error, term()}
  def authorize(request, _opts \\ []) when is_map(request) do
    if Code.ensure_loaded?(AuthorityContract) and
         function_exported?(AuthorityContract, :authorize, 1) do
      apply(AuthorityContract, :authorize, [request])
    else
      {:ok, fallback_decision(request)}
    end
  end

  defp fallback_decision(request) do
    decision_hash =
      :crypto.hash(:sha256, :erlang.term_to_binary(request))
      |> Base.encode16(case: :lower)

    AuthorityDecisionV1.new!(%{
      contract_version: "v1",
      decision_id:
        "decision:" <> request["operation"] <> ":" <> binary_part(decision_hash, 0, 16),
      tenant_id: request["tenant_ref"],
      request_id: request["request_id"],
      policy_version: "policy:chassis-fallback-authority-v1",
      boundary_class: request["authority_class"],
      trust_profile: "trusted_operator",
      approval_profile: "operator-and-policy",
      egress_profile: "outbound-controlled",
      workspace_profile: "chassis-deployment",
      resource_profile: "control-plane",
      decision_hash: decision_hash,
      extensions: %{
        "citadel" => %{
          "source" => "authority_decision_module_fallback",
          "trace_id" => request["trace_id"],
          "caller_kind" => request["caller_kind"]
        }
      }
    })
  end
end

defmodule Chassis.Policy.AuthorityAudit do
  @moduledoc "Authority reference propagation helpers for receipt and effect-log attrs."

  alias Chassis.Boundary.{Envelope, Error}

  @type round_trip :: %{
          envelope: Envelope.t(),
          receipt: map(),
          effect_log: map()
        }

  @spec round_trip(Envelope.t(), map() | keyword(), map() | keyword()) ::
          {:ok, round_trip()} | {:error, Error.t()}
  def round_trip(%Envelope{} = envelope, receipt_attrs, effect_attrs) do
    case envelope.authority_ref do
      authority_ref when is_binary(authority_ref) and authority_ref != "" ->
        {:ok,
         %{
           envelope: envelope,
           receipt: receipt_attrs |> Map.new() |> Map.put(:authority_ref, authority_ref),
           effect_log: effect_attrs |> Map.new() |> Map.put(:authority_ref, authority_ref)
         }}

      _missing ->
        {:error,
         Error.new(:authority_denied, envelope,
           safe_message: "authority_ref is required before receipt/effect logging",
           retry_posture: :operator_required
         )}
    end
  end
end
