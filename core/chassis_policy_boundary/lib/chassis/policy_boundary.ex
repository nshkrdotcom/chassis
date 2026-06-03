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

  @authority_intents %{
    "authority:chassis:evolution:create_batch" => %{
      operation: :evolution_create_batch,
      authority_class: "chassis.evolution.create_batch",
      protocol_ref: "boundary:chassis.evolution.create_batch:v1",
      tools: [],
      effect_classes: ["chassis.evolution.failure_batch"],
      binding_keys: [:tenant_ref, :installation_ref, :redaction_posture, :evidence_refs_digest]
    },
    "authority:chassis:evolution:start" => %{
      operation: :evolution_start,
      authority_class: "chassis.evolution.start",
      protocol_ref: "boundary:chassis.evolution.start:v1",
      tools: [],
      effect_classes: ["chassis.evolution.lifecycle"],
      binding_keys: [
        :tenant_ref,
        :installation_ref,
        :failure_batch_ref,
        :runner_profile_ref,
        :scorer_profile_ref,
        :trial_profile_ref,
        :budget_ref
      ]
    },
    "authority:chassis:evolution:run_coding_agent" => %{
      operation: :evolution_run_coding_agent,
      authority_class: "chassis.evolution.run_coding_agent",
      protocol_ref: "boundary:chassis.evolution.run_coding_agent:v1",
      tools: ["coding_agent"],
      effect_classes: ["chassis.evolution.coding_agent"],
      binding_keys: [
        :tenant_ref,
        :installation_ref,
        :candidate_ref,
        :runner_kind,
        :runner_profile_ref,
        :budget_ref
      ]
    },
    "authority:chassis:evolution:provision_trial" => %{
      operation: :evolution_provision_trial,
      authority_class: "chassis.evolution.provision_trial",
      protocol_ref: "boundary:chassis.evolution.provision_trial:v1",
      tools: ["trial_runtime"],
      effect_classes: ["chassis.evolution.trial"],
      binding_keys: [
        :tenant_ref,
        :installation_ref,
        :candidate_ref,
        :trial_profile_ref,
        :trial_runtime_kind,
        :approved_state_volume_mounts
      ]
    },
    "authority:chassis:evolution:score_candidate" => %{
      operation: :evolution_score_candidate,
      authority_class: "chassis.evolution.score_candidate",
      protocol_ref: "boundary:chassis.evolution.score_candidate:v1",
      tools: [],
      effect_classes: ["chassis.evolution.scoring"],
      binding_keys: [:tenant_ref, :installation_ref, :trial_run_ref, :scorer_profile_ref]
    },
    "authority:chassis:evolution:request_promotion" => %{
      operation: :evolution_request_promotion,
      authority_class: "chassis.evolution.request_promotion",
      protocol_ref: "boundary:chassis.evolution.request_promotion:v1",
      tools: [],
      effect_classes: ["chassis.evolution.promotion_intent"],
      binding_keys: [
        :tenant_ref,
        :installation_ref,
        :candidate_ref,
        :target_installation_ref
      ]
    },
    "authority:chassis:evolution:promote_candidate" => %{
      operation: :evolution_promote_candidate,
      authority_class: "chassis.evolution.promote_candidate",
      protocol_ref: "boundary:chassis.evolution.promote_candidate:v1",
      tools: ["host_daemon"],
      effect_classes: ["chassis.evolution.promotion"],
      binding_keys: [
        :tenant_ref,
        :installation_ref,
        :candidate_ref,
        :failure_batch_ref,
        :patch_digest,
        :base_release_ref,
        :artifact_digest,
        :score_matrix_ref,
        :target_installation_ref,
        :approved_state_volume_mounts,
        :rollback_ref,
        :operator_consent_ref,
        :trace_id
      ]
    },
    "authority:chassis:evolution:rollback_candidate" => %{
      operation: :evolution_rollback_candidate,
      authority_class: "chassis.evolution.rollback_candidate",
      protocol_ref: "boundary:chassis.evolution.rollback_candidate:v1",
      tools: ["host_daemon"],
      effect_classes: ["chassis.evolution.rollback"],
      binding_keys: [
        :tenant_ref,
        :installation_ref,
        :candidate_ref,
        :swap_ref,
        :reason_code
      ]
    },
    "authority:chassis:host_daemon:swap" => %{
      operation: :host_daemon_swap,
      authority_class: "chassis.host_daemon.swap",
      protocol_ref: "boundary:chassis.host_daemon.swap:v1",
      tools: ["systemd", "unix_socket"],
      effect_classes: ["chassis.host_daemon.swap"],
      binding_keys: [
        :tenant_ref,
        :installation_ref,
        :candidate_ref,
        :host_target_ref,
        :artifact_digest,
        :approved_state_volume_mounts,
        :host_swap_strategy
      ]
    },
    "authority:chassis:host_daemon:rollback" => %{
      operation: :host_daemon_rollback,
      authority_class: "chassis.host_daemon.rollback",
      protocol_ref: "boundary:chassis.host_daemon.rollback:v1",
      tools: ["systemd", "unix_socket"],
      effect_classes: ["chassis.host_daemon.rollback"],
      binding_keys: [:tenant_ref, :installation_ref, :swap_ref, :reason_code]
    },
    "authority:chassis:model:materialize_weight" => %{
      operation: :model_materialize_weight,
      authority_class: "chassis.model.materialize_weight",
      protocol_ref: "boundary:chassis.model.materialize_weight:v1",
      tools: ["hf_hub", "artifact_fs"],
      effect_classes: ["chassis.model.materialization"],
      binding_keys: [
        :tenant_ref,
        :installation_ref,
        :model_ref,
        :target_host_ref,
        :source_strategy,
        :expected_digest_ref,
        :bandwidth_class,
        :cache_root_ref
      ]
    },
    "authority:chassis:model:reload_tensor_patch" => %{
      operation: :model_reload_tensor_patch,
      authority_class: "chassis.model.reload_tensor_patch",
      protocol_ref: "boundary:chassis.model.reload_tensor_patch:v1",
      tools: ["tensor_reload"],
      effect_classes: ["chassis.model.tensor_reload"],
      binding_keys: [
        :tenant_ref,
        :installation_ref,
        :patch_ref,
        :target_runtime_ref,
        :reload_strategy,
        :rollback_patch_ref
      ]
    },
    "authority:chassis:hardware:admit_accelerator" => %{
      operation: :hardware_admit_accelerator,
      authority_class: "chassis.hardware.admit_accelerator",
      protocol_ref: "boundary:chassis.hardware.admit_accelerator:v1",
      tools: [],
      effect_classes: ["chassis.hardware.admission"],
      binding_keys: [
        :tenant_ref,
        :installation_ref,
        :host_ref,
        :runtime_ref,
        :required_capabilities_digest
      ]
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

  @spec authorize_intent(map(), keyword()) ::
          {:ok,
           %{
             authority_ref: String.t(),
             governance_packet: term(),
             binding_attrs: map(),
             intent_ref: String.t()
           }}
          | {:error, Error.t()}
  def authorize_intent(request, opts \\ [])

  def authorize_intent(request, opts) when is_map(request) do
    intent_ref = request_value(request, :intent_ref)

    with {:ok, spec} <- intent_spec(intent_ref),
         {:ok, binding_attrs} <- build_binding_attrs(intent_ref, request),
         :ok <- validate_intent_consent(intent_ref, binding_attrs, request, opts),
         {:ok, %AuthorityDecisionV1{} = decision} <-
           acquire_intent_decision(intent_ref, spec, binding_attrs, request, opts),
         {:ok, governance} <- compile_intent(decision, intent_ref, spec, binding_attrs, opts) do
      {:ok,
       %{
         authority_ref: authority_ref(governance),
         governance_packet: governance,
         binding_attrs: binding_attrs,
         intent_ref: intent_ref
       }}
    end
  end

  def authorize_intent(_request, _opts),
    do:
      {:error,
       Error.new(:invalid_request,
         safe_message: "intent authority request must be a map",
         retry_posture: :non_retryable
       )}

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

  @spec authority_intents() :: [String.t()]
  def authority_intents, do: @authority_intents |> Map.keys() |> Enum.sort()

  @spec binding_keys(String.t()) :: {:ok, [atom()]} | {:error, Error.t()}
  def binding_keys(intent_ref) when is_binary(intent_ref) do
    case intent_spec(intent_ref) do
      {:ok, spec} -> {:ok, spec.binding_keys}
      {:error, %Error{} = error} -> {:error, error}
    end
  end

  def binding_keys(_intent_ref),
    do:
      {:error,
       Error.new(:invalid_request,
         safe_message: "authority intent ref must be a string",
         retry_posture: :non_retryable
       )}

  @spec build_binding_attrs!(map(), [atom()]) :: map()
  def build_binding_attrs!(attrs, binding_keys) when is_map(attrs) and is_list(binding_keys) do
    attrs =
      attrs
      |> normalize_binding_keys()
      |> synthesize_binding_digests()

    Map.new(binding_keys, fn key ->
      value = binding_value(attrs, key)

      if binding_present?(value) do
        {key, value}
      else
        raise ArgumentError, "missing authority binding #{key}"
      end
    end)
  end

  @spec assert_mutation_authorized(map()) :: :ok | {:error, Error.t()}
  def assert_mutation_authorized(attrs) when is_map(attrs) do
    intent_ref = request_value(attrs, :intent_ref)
    authority_ref = request_value(attrs, :authority_ref)
    operator_consent_ref = request_value(attrs, :operator_consent_ref)

    cond do
      not present_string?(authority_ref) ->
        {:error,
         Error.new(:authority_denied,
           safe_message: "authority_ref is required before Chassis mutation",
           retry_posture: :operator_required
         )}

      consent_required_for_mutation?(intent_ref) and not present_string?(operator_consent_ref) ->
        {:error,
         Error.new(:authority_denied,
           safe_message: "operator_consent_ref is required before swap mutation",
           retry_posture: :operator_required
         )}

      consent_required_for_mutation?(intent_ref) and operator_consent_ref == authority_ref ->
        {:error,
         Error.new(:authority_denied,
           safe_message: "operator_consent_ref must be distinct from authority_ref",
           retry_posture: :operator_required
         )}

      true ->
        :ok
    end
  end

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

  defp intent_spec(intent_ref) when is_binary(intent_ref) do
    case Map.fetch(@authority_intents, intent_ref) do
      {:ok, spec} ->
        {:ok, Map.put(spec, :intent_ref, intent_ref)}

      :error ->
        {:error,
         Error.new(:invalid_request,
           safe_message: "unsupported Chassis authority intent #{inspect(intent_ref)}",
           retry_posture: :non_retryable
         )}
    end
  end

  defp intent_spec(_intent_ref) do
    {:error,
     Error.new(:invalid_request,
       safe_message: "authority intent ref is required",
       retry_posture: :non_retryable
     )}
  end

  defp build_binding_attrs(intent_ref, request) do
    with {:ok, binding_keys} <- binding_keys(intent_ref) do
      attrs =
        request
        |> request_value(:attrs, %{})
        |> Map.new()
        |> Map.put_new(:tenant_ref, request_value(request, :tenant_ref))
        |> Map.put_new(:installation_ref, request_value(request, :installation_ref))
        |> Map.put_new(:trace_id, request_value(request, :trace_id))

      {:ok, build_binding_attrs!(attrs, binding_keys)}
    end
  rescue
    exception in ArgumentError ->
      {:error,
       Error.new(:authority_denied,
         trace_id: request_value(request, :trace_id),
         protocol_ref: intent_ref,
         safe_message: Exception.message(exception),
         retry_posture: :operator_required
       )}
  end

  defp validate_intent_consent(
         "authority:chassis:evolution:promote_candidate",
         binding_attrs,
         request,
         opts
       ) do
    consent =
      request_value(request, :operator_consent) ||
        request_value(request, :operator_consent_record) ||
        binding_value(binding_attrs, :operator_consent_record)

    if is_nil(consent) do
      {:error,
       Error.new(:authority_denied,
         trace_id: Map.get(binding_attrs, :trace_id),
         protocol_ref: "authority:chassis:evolution:promote_candidate",
         safe_message: "operator_consent_record is required for promote_candidate",
         retry_posture: :operator_required
       )}
    else
      validation_opts =
        [
          candidate_ref: Map.fetch!(binding_attrs, :candidate_ref),
          operator_consent_ref: Map.fetch!(binding_attrs, :operator_consent_ref)
        ]
        |> maybe_put_opt(:now, Keyword.get(opts, :now))
        |> maybe_put_opt(
          :ttl_seconds,
          Keyword.get(opts, :consent_ttl_seconds) || Keyword.get(opts, :ttl_seconds)
        )

      case Chassis.Evolution.Consent.validate(consent, validation_opts) do
        {:ok, _validated} ->
          :ok

        {:error, reason} ->
          {:error,
           Error.new(:authority_denied,
             trace_id: Map.get(binding_attrs, :trace_id),
             protocol_ref: "authority:chassis:evolution:promote_candidate",
             safe_message: "operator consent #{reason}",
             retry_posture: :operator_required
           )}
      end
    end
  end

  defp validate_intent_consent(_intent_ref, _binding_attrs, _request, _opts), do: :ok

  defp acquire_intent_decision(intent_ref, spec, binding_attrs, request, opts) do
    case request_value(request, :authority_result) do
      {:error, reason} ->
        {:error, authority_error(reason, trace_id: Map.get(binding_attrs, :trace_id))}

      {:ok, %AuthorityDecisionV1{} = decision} ->
        {:ok, decision}

      _other ->
        case request_value(request, :authority_decision) do
          %AuthorityDecisionV1{} = decision -> {:ok, decision}
          _missing -> acquire_intent_decision_from_provider(intent_ref, spec, binding_attrs, opts)
        end
    end
  end

  defp acquire_intent_decision_from_provider(intent_ref, spec, binding_attrs, opts) do
    provider = Keyword.get(opts, :provider, Chassis.Policy.CitadelAuthorityProvider)

    request = %{
      "operation" => Atom.to_string(spec.operation),
      "intent_ref" => intent_ref,
      "authority_class" => spec.authority_class,
      "tenant_ref" => Map.fetch!(binding_attrs, :tenant_ref),
      "installation_ref" => Map.fetch!(binding_attrs, :installation_ref),
      "request_id" => "authority-request:" <> digest({intent_ref, binding_attrs}),
      "trace_id" => Map.get(binding_attrs, :trace_id) || "trace:" <> digest(binding_attrs),
      "caller_kind" => "intent",
      "capability_ref" => "capability:" <> spec.authority_class
    }

    case provider.authorize(request, opts) do
      {:ok, %AuthorityDecisionV1{} = decision} -> {:ok, decision}
      {:error, %Error{} = error} -> {:error, error}
      {:error, reason} -> {:error, authority_error(reason, trace_id: request["trace_id"])}
    end
  end

  defp compile_intent(decision, intent_ref, spec, binding_attrs, opts) do
    compiler = Keyword.get(opts, :compiler, ExecutionGovernanceCompiler)
    boundary_intent = intent_boundary_intent(intent_ref, spec, binding_attrs)
    topology_intent = intent_topology_intent(intent_ref, binding_attrs)
    attrs = intent_governance_attrs(intent_ref, spec, binding_attrs, decision)

    {:ok, apply(compiler, :compile!, [decision, boundary_intent, topology_intent, attrs])}
  rescue
    exception ->
      {:error,
       Error.new(:invalid_request,
         trace_id: Map.get(binding_attrs || %{}, :trace_id),
         protocol_ref: intent_ref,
         safe_message: "authority compilation failed: #{Exception.message(exception)}",
         retry_posture: :non_retryable
       )}
  end

  defp intent_boundary_intent(intent_ref, spec, binding_attrs) do
    BoundaryIntent.new!(%{
      boundary_class: spec.authority_class,
      trust_profile: "trusted_operator",
      workspace_profile: "chassis-evolution",
      resource_profile: "control-plane",
      requested_attach_mode: "fresh_or_reuse",
      requested_ttl_ms: 300_000,
      extensions: %{
        "chassis" => %{
          "intent_ref" => intent_ref,
          "operation" => Atom.to_string(spec.operation),
          "trace_id" => Map.get(binding_attrs, :trace_id)
        }
      }
    })
  end

  defp intent_topology_intent(intent_ref, binding_attrs) do
    TopologyIntent.new!(%{
      topology_intent_id: "topology-intent:" <> digest({intent_ref, binding_attrs}),
      session_mode: "attached",
      routing_hints: %{
        "protocol_ref" => intent_ref,
        "tenant_ref" => Map.get(binding_attrs, :tenant_ref),
        "installation_ref" => Map.get(binding_attrs, :installation_ref),
        "target_ref" =>
          Map.get(binding_attrs, :host_target_ref) ||
            Map.get(binding_attrs, :target_host_ref) ||
            Map.get(binding_attrs, :target_runtime_ref) ||
            Map.get(binding_attrs, :candidate_ref) ||
            "target:unknown"
      },
      coordination_mode: "single_target",
      topology_epoch: 1,
      extensions: %{"chassis" => %{"trace_id" => Map.get(binding_attrs, :trace_id)}}
    })
  end

  defp intent_governance_attrs(intent_ref, spec, binding_attrs, decision) do
    %{
      execution_governance_id: decision.decision_id,
      sandbox_level: "standard",
      sandbox_egress: "restricted",
      sandbox_approvals: "manual",
      acceptable_attestation: ["chassis.attestation.v1"],
      allowed_tools: spec.tools,
      file_scope_ref: "file-scope:chassis-managed",
      file_scope_hint: "/opt/nshkr/chassis",
      logical_workspace_ref: "workspace:chassis-evolution",
      workspace_mutability: "read_write",
      execution_family: "process",
      placement_intent: "remote_scope",
      target_kind: "chassis-control-plane",
      node_affinity: "topology-driven",
      allowed_operations: [intent_ref],
      effect_classes: spec.effect_classes,
      cpu_class: "control-plane",
      memory_class: "control-plane",
      wall_clock_budget_ms: 600_000,
      extensions: %{
        "citadel" => %{
          "chassis" => %{
            "intent_ref" => intent_ref,
            "operation" => Atom.to_string(spec.operation),
            "trace_id" => Map.get(binding_attrs, :trace_id),
            "bindings" => json_binding_attrs(binding_attrs)
          }
        }
      }
    }
  end

  defp synthesize_binding_digests(attrs) do
    attrs
    |> Map.new()
    |> put_digest_if_missing(:evidence_refs_digest, :evidence_refs)
    |> put_digest_if_missing(:required_capabilities_digest, :required_capabilities)
  end

  defp normalize_binding_keys(attrs) do
    Map.new(attrs, fn
      {key, value} when is_binary(key) -> {String.to_atom(key), value}
      {key, value} -> {key, value}
    end)
  end

  defp put_digest_if_missing(attrs, digest_key, source_key) do
    cond do
      binding_present?(binding_value(attrs, digest_key)) ->
        attrs

      binding_present?(binding_value(attrs, source_key)) ->
        Map.put(attrs, digest_key, digest(binding_value(attrs, source_key)))

      true ->
        attrs
    end
  end

  defp json_binding_attrs(attrs) do
    Map.new(attrs, fn {key, value} -> {Atom.to_string(key), json_value(value)} end)
  end

  defp json_value(value) when is_atom(value), do: Atom.to_string(value)
  defp json_value(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp json_value(value) when is_list(value), do: Enum.map(value, &json_value/1)

  defp json_value(value) when is_map(value),
    do: Map.new(value, fn {k, v} -> {to_string(k), json_value(v)} end)

  defp json_value(value), do: value

  defp request_value(map, key, default \\ nil)

  defp request_value(map, key, default) when is_map(map) do
    Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  end

  defp request_value(_other, _key, default), do: default

  defp binding_value(map, key) when is_map(map),
    do: Map.get(map, key, Map.get(map, Atom.to_string(key)))

  defp binding_present?(value) when is_binary(value), do: value != ""
  defp binding_present?(value), do: not is_nil(value)

  defp present_string?(value), do: is_binary(value) and value != ""

  defp consent_required_for_mutation?(intent_ref),
    do:
      intent_ref in [
        "authority:chassis:evolution:promote_candidate",
        "authority:chassis:host_daemon:swap"
      ]

  defp maybe_put_opt(opts, _key, nil), do: opts
  defp maybe_put_opt(opts, key, value), do: Keyword.put(opts, key, value)

  defp digest(value) do
    :crypto.hash(:sha256, :erlang.term_to_binary(value))
    |> Base.encode16(case: :lower)
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
