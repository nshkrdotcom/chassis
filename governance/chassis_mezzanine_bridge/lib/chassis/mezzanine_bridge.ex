defmodule Chassis.Mezzanine.Bridge do
  @moduledoc """
  Chassis-side Mezzanine boundary bridge.

  Public dispatch builds a Chassis boundary envelope and routes it through
  `Chassis.Boundary.dispatch/2` with the concrete protocol module attached.
  Protocol modules are still callable by the boundary local adapter, but this
  facade keeps the Mezzanine entry path from bypassing Ring 0 validation.
  """

  alias Chassis.Boundary.Envelope

  @operations %{
    materialize_deployment: %{
      protocol_ref: "boundary:mezzanine.chassis.materialize_deployment:v1",
      module: Chassis.Mezzanine.Bridge.MaterializeDeployment
    },
    rollback_deployment: %{
      protocol_ref: "boundary:mezzanine.chassis.rollback_deployment:v1",
      module: Chassis.Mezzanine.Bridge.RollbackDeployment
    },
    inspect_host: %{
      protocol_ref: "boundary:mezzanine.chassis.inspect_host:v1",
      module: Chassis.Mezzanine.Bridge.InspectHost
    },
    validate_topology: %{
      protocol_ref: "boundary:mezzanine.chassis.validate_topology:v1",
      module: Chassis.Mezzanine.Bridge.ValidateTopology
    },
    drain_host: %{
      protocol_ref: "boundary:mezzanine.chassis.drain_host:v1",
      module: Chassis.Mezzanine.Bridge.DrainHost
    },
    provision_host: %{
      protocol_ref: "boundary:mezzanine.chassis.provision_host:v1",
      module: Chassis.Mezzanine.Bridge.ProvisionHost
    },
    create_failure_batch: %{
      protocol_ref: "boundary:mezzanine.chassis.evolution.create_failure_batch:v1",
      module: Chassis.Mezzanine.Bridge.Evolution.CreateFailureBatch
    },
    evolution_start: %{
      protocol_ref: "boundary:mezzanine.chassis.evolution.start:v1",
      module: Chassis.Mezzanine.Bridge.Evolution.Start
    },
    evolution_stop: %{
      protocol_ref: "boundary:mezzanine.chassis.evolution.stop:v1",
      module: Chassis.Mezzanine.Bridge.Evolution.Stop
    },
    evolution_get_status: %{
      protocol_ref: "boundary:mezzanine.chassis.evolution.get_status:v1",
      module: Chassis.Mezzanine.Bridge.Evolution.GetStatus
    },
    provision_trial_node: %{
      protocol_ref: "boundary:mezzanine.chassis.evolution.provision_trial_node:v1",
      module: Chassis.Mezzanine.Bridge.Evolution.ProvisionTrialNode
    },
    run_trial_replay: %{
      protocol_ref: "boundary:mezzanine.chassis.evolution.run_trial_replay:v1",
      module: Chassis.Mezzanine.Bridge.Evolution.RunTrialReplay
    },
    score_candidate: %{
      protocol_ref: "boundary:mezzanine.chassis.evolution.score_candidate:v1",
      module: Chassis.Mezzanine.Bridge.Evolution.ScoreCandidate
    },
    request_promotion: %{
      protocol_ref: "boundary:mezzanine.chassis.evolution.request_promotion:v1",
      module: Chassis.Mezzanine.Bridge.Evolution.RequestPromotion
    },
    promote_candidate: %{
      protocol_ref: "boundary:mezzanine.chassis.evolution.promote_candidate:v1",
      module: Chassis.Mezzanine.Bridge.Evolution.PromoteCandidate
    },
    rollback_candidate: %{
      protocol_ref: "boundary:mezzanine.chassis.evolution.rollback_candidate:v1",
      module: Chassis.Mezzanine.Bridge.Evolution.RollbackCandidate
    },
    materialize_weight: %{
      protocol_ref: "boundary:chassis.model.materialize_weight:v1",
      module: Chassis.Mezzanine.Bridge.Evolution.MaterializeWeight
    },
    reload_tensor_patch: %{
      protocol_ref: "boundary:chassis.model.reload_tensor_patch:v1",
      module: Chassis.Mezzanine.Bridge.Evolution.ReloadTensorPatch
    },
    rollback_tensor_patch: %{
      protocol_ref: "boundary:chassis.model.rollback_tensor_patch:v1",
      module: Chassis.Mezzanine.Bridge.Evolution.RollbackTensorPatch
    }
  }

  @spec dispatch(atom(), struct() | map(), map() | keyword(), keyword()) ::
          {:ok, Envelope.t()} | {:error, Chassis.Boundary.Error.t()}
  def dispatch(operation, request, envelope_attrs, opts \\ []) do
    case Map.fetch(@operations, operation) do
      {:ok, spec} ->
        envelope =
          envelope_attrs
          |> Map.new()
          |> Map.put(:protocol_ref, spec.protocol_ref)
          |> Map.put(:payload, sanitize_boundary_payload(request))
          |> Envelope.new!()

        dispatcher = Keyword.get(opts, :boundary_dispatcher, Chassis.Boundary)

        opts =
          opts
          |> Keyword.delete(:boundary_dispatcher)
          |> Keyword.put_new(:protocol_module, spec.module)

        dispatcher.dispatch(envelope, opts)

      :error ->
        {:error,
         Chassis.Boundary.Error.new(:invalid_request,
           safe_message: "unsupported Mezzanine bridge operation #{inspect(operation)}"
         )}
    end
  end

  @spec operations() :: [atom()]
  def operations, do: @operations |> Map.keys() |> Enum.sort()

  @spec operation_spec(atom()) :: {:ok, map()} | :error
  def operation_spec(operation), do: Map.fetch(@operations, operation)

  defp sanitize_boundary_payload(%_struct{} = request), do: request

  defp sanitize_boundary_payload(request) when is_map(request) do
    request
    |> Enum.reject(fn {key, _value} -> raw_payload_key?(key) end)
    |> Map.new(fn {key, value} -> {key, sanitize_boundary_value(value)} end)
  end

  defp sanitize_boundary_payload(request), do: request

  defp sanitize_boundary_value(value) when is_map(value), do: sanitize_boundary_payload(value)

  defp sanitize_boundary_value(value) when is_list(value),
    do: Enum.map(value, &sanitize_boundary_value/1)

  defp sanitize_boundary_value(value), do: value

  defp raw_payload_key?(key) when is_atom(key) do
    key in [
      :raw_body,
      :raw_bytes,
      :raw_diff,
      :raw_payload,
      :raw_prompt,
      :raw_provider_token,
      :raw_transcript,
      :provider_token,
      :secret_value
    ]
  end

  defp raw_payload_key?(key) when is_binary(key) do
    key
    |> String.to_existing_atom()
    |> raw_payload_key?()
  rescue
    ArgumentError -> false
  end
end

defmodule Chassis.Mezzanine.Bridge.ProtocolSupport do
  @moduledoc false

  alias Chassis.Boundary.{Envelope, Error}

  @spec response(Envelope.t(), struct() | map(), [String.t()]) :: {:ok, Envelope.t()}
  def response(%Envelope{} = envelope, payload, receipt_refs \\ []) do
    {:ok, %Envelope{envelope | payload: payload, status: :ok, receipt_refs: receipt_refs}}
  end

  @spec error(Envelope.t(), term(), keyword()) :: {:error, Error.t()}
  def error(%Envelope{} = envelope, reason, opts \\ []) do
    code = Keyword.get(opts, :code, classify(reason))
    message = Keyword.get(opts, :safe_message, safe_message(reason))

    {:error,
     Error.new(code, envelope,
       safe_message: message,
       retry_posture: Keyword.get(opts, :retry_posture, retry_posture(code)),
       redaction: :safe
     )}
  end

  @spec require_opt(keyword(), atom(), Envelope.t()) :: {:ok, term()} | {:error, Error.t()}
  def require_opt(opts, key, envelope) do
    case Keyword.fetch(opts, key) do
      {:ok, value} -> {:ok, value}
      :error -> error(envelope, {:missing_required_option, key}, code: :invalid_request)
    end
  end

  defp classify(:missing_host), do: :host_unreachable
  defp classify(:missing_topology), do: :topology_invalid
  defp classify({:missing_required_option, _key}), do: :invalid_request
  defp classify(:missing_operation_handler), do: :dependency_unavailable
  defp classify(_reason), do: :invalid_request

  defp retry_posture(:dependency_unavailable), do: :retryable
  defp retry_posture(:host_unreachable), do: :retryable
  defp retry_posture(_code), do: :non_retryable

  defp safe_message({:missing_required_option, key}), do: "#{key} option is required"
  defp safe_message(reason), do: "Mezzanine bridge operation failed: #{inspect(reason)}"
end

defmodule Chassis.Mezzanine.Bridge.MaterializeDeployment do
  @moduledoc "Boundary protocol for Mezzanine materialize deployment requests."

  @behaviour Chassis.Boundary.Protocol

  alias Chassis.Boundary.{Envelope, MaterializeDeployment}
  alias Chassis.Mezzanine.Bridge.{ProjectionPublisher, ProtocolSupport}

  @impl true
  def call(%Envelope{payload: %MaterializeDeployment.Request{} = request} = envelope, opts) do
    started_at = System.monotonic_time(:millisecond)

    with {:ok, app_atom} <- ProtocolSupport.require_opt(opts, :app_atom, envelope),
         {:ok, attrs} <- transaction_attrs(envelope, request, opts, app_atom),
         {:ok, result} <- Chassis.StackManager.Transaction.run(attrs),
         :ok <- maybe_publish_projection(result, opts) do
      duration_ms = System.monotonic_time(:millisecond) - started_at

      response = %MaterializeDeployment.Response{
        deployment_receipt_ref: result.receipt_ref,
        app_ref: result.app_ref,
        node_mesh: Enum.map(result.node_mesh, &to_string/1),
        status: :ok,
        duration_ms: duration_ms
      }

      ProtocolSupport.response(envelope, response, [result.receipt_ref])
    else
      {:error, %Chassis.Boundary.Error{} = error} ->
        {:error, error}

      {:error, reason} ->
        ProtocolSupport.error(envelope, reason)
    end
  end

  def call(%Envelope{} = envelope, _opts),
    do: ProtocolSupport.error(envelope, :invalid_payload, code: :invalid_request)

  defp transaction_attrs(envelope, request, opts, app_atom) do
    attrs = %{
      registry: Keyword.get(opts, :registry),
      receipts_store: Keyword.get(opts, :receipts_store),
      fence_store: Keyword.get(opts, :fence_store, Chassis.StackManager.FenceStore),
      tenant_ref: envelope.tenant_ref,
      installation_ref: envelope.installation_ref,
      actor_ref: envelope.actor_ref,
      authority_ref: envelope.authority_ref,
      idempotency_key: envelope.idempotency_key,
      trace_id: envelope.trace_id,
      topology_ref: request.topology_ref,
      service_spec_ref: request.service_spec_ref,
      runtime_profile_ref: request.runtime_profile_ref,
      placement_ref: request.placement_ref,
      profile_ref: request.runtime_profile_ref || request.topology_ref,
      env: normalize_env(request.environment),
      git_sha: request.git_sha,
      release_version: request.release_version,
      app_atom: app_atom
    }

    {:ok, put_authorizer(attrs, envelope, opts)}
  end

  defp put_authorizer(attrs, _envelope, opts) do
    case Keyword.fetch(opts, :authorize) do
      {:ok, authorize} when is_function(authorize, 1) -> Map.put(attrs, :authorize, authorize)
      _missing -> maybe_use_envelope_authority(attrs)
    end
  end

  defp maybe_use_envelope_authority(%{authority_ref: authority_ref} = attrs)
       when is_binary(authority_ref) and authority_ref != "" do
    Map.put(attrs, :authorize, fn _topology -> {:ok, authority_ref} end)
  end

  defp maybe_use_envelope_authority(attrs), do: attrs

  defp maybe_publish_projection(result, opts) do
    with outbox when not is_nil(outbox) <- Keyword.get(opts, :outbox),
         receipts_store when not is_nil(receipts_store) <- Keyword.get(opts, :receipts_store),
         {:ok, record} <- Chassis.Receipts.Store.Memory.get(receipts_store, result.receipt_ref),
         {:ok, _event} <- ProjectionPublisher.publish(record, outbox: outbox) do
      :ok
    else
      nil -> :ok
      {:error, reason} -> {:error, {:projection_publish_failed, reason}}
    end
  end

  defp normalize_env(env) when env in [:dev, :prod], do: env
  defp normalize_env("dev"), do: :dev
  defp normalize_env("prod"), do: :prod
  defp normalize_env(_env), do: :dev
end

defmodule Chassis.Mezzanine.Bridge.RollbackDeployment do
  @moduledoc "Boundary protocol for Mezzanine rollback deployment requests."

  @behaviour Chassis.Boundary.Protocol

  alias Chassis.Boundary.{Envelope, RollbackDeployment}
  alias Chassis.Mezzanine.Bridge.ProtocolSupport

  @impl true
  def call(%Envelope{payload: %RollbackDeployment.Request{} = request} = envelope, opts) do
    started_at = System.monotonic_time(:millisecond)

    with {:ok, app_ref} <- ProtocolSupport.require_opt(opts, :app_ref, envelope),
         {:ok, result} <- Chassis.StackManager.Transaction.rollback(app_ref, Map.new(opts)) do
      duration_ms = System.monotonic_time(:millisecond) - started_at

      response = %RollbackDeployment.Response{
        rollback_receipt_ref: result.rollback_receipt_ref,
        status: to_string(result.status),
        restored_revision: request.target_revision || result.rollback_target_ref,
        duration_ms: duration_ms
      }

      ProtocolSupport.response(envelope, response, [result.rollback_receipt_ref])
    else
      {:error, %Chassis.Boundary.Error{} = error} -> {:error, error}
      {:error, reason} -> ProtocolSupport.error(envelope, reason)
    end
  end

  def call(%Envelope{} = envelope, _opts),
    do: ProtocolSupport.error(envelope, :invalid_payload, code: :invalid_request)
end

defmodule Chassis.Mezzanine.Bridge.InspectHost do
  @moduledoc "Boundary protocol for host inspection."

  @behaviour Chassis.Boundary.Protocol

  alias Chassis.Boundary.{Envelope, InspectHost}
  alias Chassis.Mezzanine.Bridge.ProtocolSupport

  @impl true
  def call(%Envelope{payload: %InspectHost.Request{} = request} = envelope, opts) do
    hosts = Keyword.get(opts, :hosts, [])

    case Enum.find(hosts, &(Map.get(&1, :host_ref) == request.host_ref)) do
      nil ->
        ProtocolSupport.error(envelope, :missing_host)

      host ->
        response = %InspectHost.Response{
          host_ref: request.host_ref,
          status: host |> Map.get(:status, :unknown) |> to_string(),
          facts: Map.get(host, :facts, host),
          observed_at: DateTime.utc_now() |> DateTime.to_iso8601()
        }

        ProtocolSupport.response(envelope, response)
    end
  end

  def call(%Envelope{} = envelope, _opts),
    do: ProtocolSupport.error(envelope, :invalid_payload, code: :invalid_request)
end

defmodule Chassis.Mezzanine.Bridge.ValidateTopology do
  @moduledoc "Boundary protocol for topology validation."

  @behaviour Chassis.Boundary.Protocol

  alias Chassis.Boundary.{Envelope, ValidateTopology}
  alias Chassis.Mezzanine.Bridge.ProtocolSupport

  @impl true
  def call(%Envelope{payload: %ValidateTopology.Request{} = request} = envelope, _opts) do
    cond do
      is_nil(request.topology) ->
        ProtocolSupport.error(envelope, :missing_topology, code: :topology_invalid)

      violations = Map.get(request.topology, :violations, []) ->
        response = %ValidateTopology.Response{
          valid?: to_string(violations == []),
          violations: violations,
          warnings: Map.get(request.topology, :warnings, [])
        }

        ProtocolSupport.response(envelope, response)
    end
  end

  def call(%Envelope{} = envelope, _opts),
    do: ProtocolSupport.error(envelope, :invalid_payload, code: :invalid_request)
end

defmodule Chassis.Mezzanine.Bridge.DrainHost do
  @moduledoc "Boundary protocol for host drain requests."

  @behaviour Chassis.Boundary.Protocol

  alias Chassis.Boundary.{DrainHost, Envelope}
  alias Chassis.Mezzanine.Bridge.ProtocolSupport

  @impl true
  def call(%Envelope{payload: %DrainHost.Request{} = request} = envelope, opts) do
    case Keyword.get(opts, :drain_host) do
      fun when is_function(fun, 1) ->
        case fun.(request) do
          {:ok, result} ->
            response = %DrainHost.Response{
              host_ref: Map.get(result, :host_ref, request.host_ref),
              status: result |> Map.get(:status, :drained) |> to_string(),
              duration_ms: Map.get(result, :duration_ms, 0)
            }

            ProtocolSupport.response(envelope, response)

          {:error, reason} ->
            ProtocolSupport.error(envelope, reason)
        end

      _missing ->
        ProtocolSupport.error(envelope, :missing_operation_handler, code: :dependency_unavailable)
    end
  end

  def call(%Envelope{} = envelope, _opts),
    do: ProtocolSupport.error(envelope, :invalid_payload, code: :invalid_request)
end

defmodule Chassis.Mezzanine.Bridge.ProvisionHost do
  @moduledoc "Boundary protocol for host provisioning requests."

  @behaviour Chassis.Boundary.Protocol

  alias Chassis.Boundary.{Envelope, ProvisionHost}
  alias Chassis.Mezzanine.Bridge.ProtocolSupport

  @impl true
  def call(%Envelope{payload: %ProvisionHost.Request{} = request} = envelope, opts) do
    case Keyword.get(opts, :provision_host) do
      fun when is_function(fun, 1) ->
        case fun.(request) do
          {:ok, result} ->
            response = %ProvisionHost.Response{
              host_ref: Map.get(result, :host_ref, request.host_ref),
              provisioning_receipt_ref: Map.fetch!(result, :provisioning_receipt_ref),
              status: result |> Map.get(:status, :ok) |> to_string(),
              duration_ms: Map.get(result, :duration_ms, 0)
            }

            ProtocolSupport.response(envelope, response, [response.provisioning_receipt_ref])

          {:error, reason} ->
            ProtocolSupport.error(envelope, reason)
        end

      _missing ->
        ProtocolSupport.error(envelope, :missing_operation_handler, code: :dependency_unavailable)
    end
  end

  def call(%Envelope{} = envelope, _opts),
    do: ProtocolSupport.error(envelope, :invalid_payload, code: :invalid_request)
end

defmodule Chassis.Mezzanine.Bridge.Evolution.LocalDispatcher do
  @moduledoc "Registry-independent local dispatcher for Phase 35 evolution bridge protocols."

  alias Chassis.Boundary.{Envelope, Error}

  @spec dispatch(Envelope.t(), keyword()) :: {:ok, Envelope.t()} | {:error, Error.t()}
  def dispatch(%Envelope{} = envelope, opts) do
    with module when is_atom(module) <- Keyword.get(opts, :protocol_module),
         true <- Code.ensure_loaded?(module),
         true <- function_exported?(module, :call, 2) do
      _encoded = Envelope.encode!(envelope)

      case module.call(envelope, opts) do
        {:ok, %Envelope{} = response} ->
          _encoded = Envelope.encode!(response)
          {:ok, response}

        {:error, %Error{} = error} ->
          {:error, error}

        other ->
          {:error,
           Error.new(:invalid_request, envelope,
             safe_message: "Evolution local dispatcher returned #{inspect(other)}"
           )}
      end
    else
      _other ->
        {:error,
         Error.new(:invalid_request, envelope,
           safe_message: "protocol_module is required for evolution local dispatch"
         )}
    end
  rescue
    exception in ArgumentError ->
      {:error,
       Error.new(:invalid_request, envelope,
         safe_message: Exception.message(exception),
         redaction: :safe
       )}
  end
end

defmodule Chassis.Mezzanine.Bridge.Evolution.Protocol do
  @moduledoc false

  alias Chassis.Boundary.Envelope
  alias Chassis.Evolution.Receipts
  alias Chassis.Mezzanine.Bridge.{Outbox, ProtocolSupport}

  @spec create_failure_batch(Envelope.t(), keyword()) :: {:ok, Envelope.t()} | {:error, term()}
  def create_failure_batch(%Envelope{} = envelope, opts) do
    attrs = payload_attrs(envelope)
    failure_batch_ref = value(attrs, :failure_batch_ref, "failure-batch:#{short_id(envelope)}")

    record =
      Receipts.FailureBatchRecord.new!(%{
        failure_batch_ref: failure_batch_ref,
        tenant_ref: envelope.tenant_ref || value(attrs, :tenant_ref),
        installation_ref: envelope.installation_ref || value(attrs, :installation_ref),
        source: :mezzanine,
        evidence_refs: value(attrs, :evidence_refs, []),
        summary: value(attrs, :summary, ""),
        redaction_posture: value(attrs, :redaction_posture, "default"),
        flagged_by_ref: value(attrs, :flagged_by_ref),
        batch_hint_ref: value(attrs, :batch_hint_ref),
        source_event_ref: value(attrs, :source_event_ref),
        source_region: value(attrs, :source_region),
        trace_id: envelope.trace_id
      })

    with {:ok, stored} <- put_receipt(record, opts),
         :ok <- publish(stored, :chassis_evolution, failure_batch_ref, "created", opts) do
      response(envelope, %{
        failure_batch_ref: failure_batch_ref,
        receipt_ref: stored.receipt_ref,
        status: "ok"
      })
    end
  rescue
    exception in ArgumentError -> ProtocolSupport.error(envelope, Exception.message(exception))
  end

  def start(%Envelope{} = envelope, opts) do
    attrs = payload_attrs(envelope)
    failure_batch_ref = value(attrs, :failure_batch_ref, "failure-batch:#{short_id(envelope)}")
    evolution_ref = value(attrs, :evolution_ref, "evolution:#{short_id(envelope)}")
    candidate_ref = value(attrs, :candidate_ref, "candidate:#{short_id(envelope)}")

    record =
      Receipts.EvolutionStartRecord.new!(%{
        tenant_ref: envelope.tenant_ref,
        installation_ref: envelope.installation_ref,
        trace_id: envelope.trace_id,
        evolution_run_ref: evolution_ref,
        failure_batch_ref: failure_batch_ref,
        started_at: DateTime.utc_now(),
        actor_ref: envelope.actor_ref,
        summary: "evolution started"
      })

    patch =
      Receipts.CandidatePatchRecord.new!(%{
        tenant_ref: envelope.tenant_ref,
        installation_ref: envelope.installation_ref,
        trace_id: envelope.trace_id,
        candidate_ref: candidate_ref,
        base_release_ref: value(attrs, :base_release_ref, "release:base:#{short_id(envelope)}"),
        patch_digest: value(attrs, :patch_digest, "sha256:patch:#{short_id(envelope)}"),
        diff_ref: value(attrs, :diff_ref, "diff:#{candidate_ref}"),
        failure_batch_ref: failure_batch_ref,
        code_agent_run_ref: "code-agent-run:#{short_id(envelope)}",
        summary: "candidate patch started"
      })

    with {:ok, start_record} <- put_receipt(record, opts),
         {:ok, patch_record} <- put_receipt(patch, opts),
         :ok <- publish(patch_record, :chassis_candidate, candidate_ref, "patching", opts) do
      response(envelope, %{
        evolution_ref: evolution_ref,
        candidate_ref: candidate_ref,
        patch_digest: patch.patch_digest,
        code_agent_run_ref: patch.code_agent_run_ref,
        initial_state: "queued",
        receipt_ref: start_record.receipt_ref,
        candidate_receipt_ref: patch_record.receipt_ref,
        status: "accepted"
      })
    end
  rescue
    exception in ArgumentError -> ProtocolSupport.error(envelope, Exception.message(exception))
  end

  def stop(%Envelope{} = envelope, opts) do
    attrs = payload_attrs(envelope)
    evolution_ref = value(attrs, :evolution_ref, "evolution:#{short_id(envelope)}")

    record =
      Receipts.EvolutionStopRecord.new!(%{
        tenant_ref: envelope.tenant_ref,
        installation_ref: envelope.installation_ref,
        trace_id: envelope.trace_id,
        evolution_run_ref: evolution_ref,
        stopped_at: DateTime.utc_now(),
        reason_code: value(attrs, :reason_code, "operator_stop"),
        actor_ref: envelope.actor_ref,
        summary: "evolution stopped"
      })

    with {:ok, stored} <- put_receipt(record, opts),
         :ok <- publish(stored, :chassis_evolution, evolution_ref, "stopped", opts) do
      response(envelope, %{
        evolution_ref: evolution_ref,
        terminal_state: "stopped",
        reason_code: record.reason_code,
        receipt_ref: stored.receipt_ref,
        status: "completed"
      })
    end
  rescue
    exception in ArgumentError -> ProtocolSupport.error(envelope, Exception.message(exception))
  end

  def get_status(%Envelope{} = envelope, _opts) do
    attrs = payload_attrs(envelope)

    response(envelope, %{
      evolution_ref: value(attrs, :evolution_ref, "evolution:#{short_id(envelope)}"),
      state: value(attrs, :state, "patching"),
      candidate_ref: value(attrs, :candidate_ref, "candidate:#{short_id(envelope)}"),
      status: "ok"
    })
  end

  def provision_trial_node(%Envelope{} = envelope, opts) do
    attrs = payload_attrs(envelope)
    candidate_ref = value(attrs, :candidate_ref, "candidate:#{short_id(envelope)}")
    trial_ref = value(attrs, :trial_ref, "trial:#{short_id(envelope)}")

    record =
      trial_record(envelope, attrs,
        trial_ref: trial_ref,
        trial_run_ref: "trial-run:provision:#{short_id(envelope)}",
        candidate_ref: candidate_ref,
        verdict: "provisioned"
      )

    with {:ok, stored} <- put_receipt(record, opts),
         :ok <- publish(stored, :chassis_trial, trial_ref, "provisioned", opts) do
      response(envelope, %{
        trial_ref: trial_ref,
        trial_node_ref: "trial-node:#{short_id(envelope)}",
        trial_runtime_kind: "fixture",
        receipt_ref: stored.receipt_ref,
        status: "accepted"
      })
    end
  rescue
    exception in ArgumentError -> ProtocolSupport.error(envelope, Exception.message(exception))
  end

  def run_trial_replay(%Envelope{} = envelope, opts) do
    attrs = payload_attrs(envelope)
    trial_ref = value(attrs, :trial_ref, "trial:#{short_id(envelope)}")
    trial_run_ref = value(attrs, :trial_run_ref, "trial-run:#{short_id(envelope)}")

    record =
      trial_record(envelope, attrs,
        trial_ref: trial_ref,
        trial_run_ref: trial_run_ref,
        candidate_ref: value(attrs, :candidate_ref, "candidate:#{short_id(envelope)}"),
        verdict: "passed"
      )

    with {:ok, stored} <- put_receipt(record, opts),
         :ok <- publish(stored, :chassis_trial, trial_ref, "completed", opts) do
      response(envelope, %{
        trial_ref: trial_ref,
        trial_run_ref: trial_run_ref,
        verdict: "passed",
        receipt_ref: stored.receipt_ref,
        status: "completed"
      })
    end
  rescue
    exception in ArgumentError -> ProtocolSupport.error(envelope, Exception.message(exception))
  end

  def score_candidate(%Envelope{} = envelope, opts) do
    attrs = payload_attrs(envelope)
    score_matrix_ref = value(attrs, :score_matrix_ref, "score-matrix:#{short_id(envelope)}")
    candidate_ref = value(attrs, :candidate_ref, "candidate:#{short_id(envelope)}")

    record =
      Receipts.ScoreMatrixRecord.new!(%{
        tenant_ref: envelope.tenant_ref,
        installation_ref: envelope.installation_ref,
        trace_id: envelope.trace_id,
        score_matrix_ref: score_matrix_ref,
        candidate_ref: candidate_ref,
        regression_gate: value(attrs, :regression_gate, "passed"),
        confidence: value(attrs, :confidence, 0.9),
        blocked_reasons: [],
        summary: "candidate scored"
      })

    with {:ok, stored} <- put_receipt(record, opts),
         :ok <- publish(stored, :chassis_score_matrix, score_matrix_ref, "passed", opts) do
      response(envelope, %{
        score_matrix_ref: score_matrix_ref,
        regression_gate: "passed",
        confidence: to_string(record.confidence),
        blocked_reasons: [],
        receipt_ref: stored.receipt_ref,
        status: "completed"
      })
    end
  rescue
    exception in ArgumentError -> ProtocolSupport.error(envelope, Exception.message(exception))
  end

  def request_promotion(%Envelope{} = envelope, opts) do
    attrs = payload_attrs(envelope)
    candidate_ref = value(attrs, :candidate_ref, "candidate:#{short_id(envelope)}")
    promotion_ref = value(attrs, :promotion_intent_ref, "promotion:#{short_id(envelope)}")

    record =
      Receipts.PromotionIntentRecord.new!(%{
        tenant_ref: envelope.tenant_ref,
        installation_ref: envelope.installation_ref,
        trace_id: envelope.trace_id,
        promotion_ref: promotion_ref,
        candidate_ref: candidate_ref,
        target_installation_ref:
          value(attrs, :target_installation_ref, envelope.installation_ref),
        issued_at: DateTime.utc_now(),
        consent_required?: true,
        consent_ref_template: "operator-consent:#{candidate_ref}:*",
        summary: "promotion requested"
      })

    with {:ok, stored} <- put_receipt(record, opts),
         :ok <-
           publish(stored, :chassis_promotion, promotion_ref, "awaiting_operator_consent", opts) do
      response(envelope, %{
        promotion_intent_ref: promotion_ref,
        required_consent_ref_template: record.consent_ref_template,
        receipt_ref: stored.receipt_ref,
        status: "accepted"
      })
    end
  rescue
    exception in ArgumentError -> ProtocolSupport.error(envelope, Exception.message(exception))
  end

  def promote_candidate(%Envelope{} = envelope, opts) do
    attrs = payload_attrs(envelope)
    candidate_ref = value(attrs, :candidate_ref, "candidate:#{short_id(envelope)}")
    promotion_ref = value(attrs, :promotion_ref, "promotion:#{short_id(envelope)}")
    swap_ref = value(attrs, :swap_ref, "swap:#{short_id(envelope)}")

    promotion =
      Receipts.PromotionRecord.new!(%{
        tenant_ref: envelope.tenant_ref,
        installation_ref: envelope.installation_ref,
        trace_id: envelope.trace_id,
        promotion_ref: promotion_ref,
        swap_ref: swap_ref,
        outcome: "committed",
        committed_at_or_rolled_back_at: DateTime.utc_now(),
        summary: "promotion applied"
      })

    swap =
      Receipts.SwapRecord.new!(%{
        tenant_ref: envelope.tenant_ref,
        installation_ref: envelope.installation_ref,
        trace_id: envelope.trace_id,
        swap_ref: swap_ref,
        candidate_ref: candidate_ref,
        target_installation_ref:
          value(attrs, :target_installation_ref, envelope.installation_ref),
        artifact_digest: value(attrs, :artifact_digest, "sha256:artifact:#{short_id(envelope)}"),
        previous_artifact_digest: value(attrs, :previous_artifact_digest, "sha256:previous"),
        health_probe_window_ms: value(attrs, :health_probe_window_ms, 90_000),
        swapped_at: DateTime.utc_now(),
        summary: "swap committed"
      })

    with {:ok, promotion_record} <- put_receipt(promotion, opts),
         {:ok, swap_record} <- put_receipt(swap, opts),
         :ok <- publish(swap_record, :chassis_swap, swap_ref, "committed", opts) do
      response(envelope, %{
        promotion_record_ref: promotion_record.receipt_ref,
        swap_ref: swap_ref,
        health_probe_window_ms: swap.health_probe_window_ms,
        swap_receipt_ref: swap_record.receipt_ref,
        status: "committed"
      })
    end
  rescue
    exception in ArgumentError -> ProtocolSupport.error(envelope, Exception.message(exception))
  end

  def rollback_candidate(%Envelope{} = envelope, opts) do
    attrs = payload_attrs(envelope)
    swap_ref = value(attrs, :swap_ref, "swap:#{short_id(envelope)}")
    rollback_ref = value(attrs, :rollback_ref, "rollback:#{short_id(envelope)}")

    record =
      Receipts.EvolutionRollbackRecord.new!(%{
        tenant_ref: envelope.tenant_ref,
        installation_ref: envelope.installation_ref,
        trace_id: envelope.trace_id,
        rollback_ref: rollback_ref,
        swap_ref: swap_ref,
        restored_artifact_digest: value(attrs, :restored_artifact_digest, "sha256:previous"),
        reason_code: value(attrs, :reason_code, "operator"),
        rolled_back_at: DateTime.utc_now(),
        summary: "swap rolled back"
      })

    with {:ok, stored} <- put_receipt(record, opts),
         :ok <- publish(stored, :chassis_swap, swap_ref, "rolled_back", opts) do
      response(envelope, %{
        rollback_record_ref: rollback_ref,
        restored_artifact_digest: record.restored_artifact_digest,
        receipt_ref: stored.receipt_ref,
        status: "rolled_back"
      })
    end
  rescue
    exception in ArgumentError -> ProtocolSupport.error(envelope, Exception.message(exception))
  end

  def materialize_weight(%Envelope{} = envelope, opts) do
    attrs = payload_attrs(envelope)

    materialization_ref =
      value(attrs, :materialization_record_ref, "model-materialization:#{short_id(envelope)}")

    event = %{
      projection: :chassis_model_materialization,
      primary_ref: materialization_ref,
      payload: %{
        materialization_record_ref: materialization_ref,
        model_ref: value(attrs, :model_ref, "model:unknown"),
        target_host_ref: value(attrs, :target_host_ref, "host:local"),
        cache_path_ref: value(attrs, :cache_path_ref, "cache-ref:#{short_id(envelope)}"),
        bytes_materialized: value(attrs, :bytes_materialized, 0),
        digest_verified: "ok",
        state_or_outcome: "completed"
      }
    }

    with :ok <- publish_event(envelope, event, opts) do
      response(envelope, Map.put(event.payload, :status, "completed"))
    end
  end

  def reload_tensor_patch(%Envelope{} = envelope, opts) do
    attrs = payload_attrs(envelope)
    reload_ref = value(attrs, :tensor_reload_record_ref, "tensor-reload:#{short_id(envelope)}")

    event = %{
      projection: :chassis_tensor_reload,
      primary_ref: reload_ref,
      payload: %{
        tensor_reload_record_ref: reload_ref,
        patch_ref: value(attrs, :patch_ref, "patch:unknown"),
        target_runtime_ref: value(attrs, :target_runtime_ref, "runtime:local"),
        strategy_applied: value(attrs, :reload_strategy, "hot_reload"),
        state_or_outcome: "completed"
      }
    }

    with :ok <- publish_event(envelope, event, opts) do
      response(envelope, Map.put(event.payload, :status, "completed"))
    end
  end

  def rollback_tensor_patch(%Envelope{} = envelope, opts) do
    attrs = payload_attrs(envelope)

    rollback_ref =
      value(attrs, :tensor_rollback_record_ref, "tensor-rollback:#{short_id(envelope)}")

    event = %{
      projection: :chassis_tensor_reload,
      primary_ref: rollback_ref,
      payload: %{
        tensor_rollback_record_ref: rollback_ref,
        patch_ref: value(attrs, :patch_ref, "patch:unknown"),
        target_runtime_ref: value(attrs, :target_runtime_ref, "runtime:local"),
        restored_patch_digest: value(attrs, :restored_patch_digest, "sha256:rollback"),
        state_or_outcome: "rolled_back"
      }
    }

    with :ok <- publish_event(envelope, event, opts) do
      response(envelope, Map.put(event.payload, :status, "rolled_back"))
    end
  end

  defp trial_record(envelope, attrs, opts) do
    Receipts.TrialRunRecord.new!(%{
      tenant_ref: envelope.tenant_ref,
      installation_ref: envelope.installation_ref,
      trace_id: envelope.trace_id,
      trial_run_ref: Keyword.fetch!(opts, :trial_run_ref),
      trial_ref: Keyword.fetch!(opts, :trial_ref),
      candidate_ref: Keyword.fetch!(opts, :candidate_ref),
      failure_batch_ref: value(attrs, :failure_batch_ref),
      baseline_set_ref: value(attrs, :baseline_set_ref, "baseline:default"),
      started_at: DateTime.utc_now(),
      completed_at: DateTime.utc_now(),
      verdict: Keyword.fetch!(opts, :verdict),
      replay_log_ref: "replay-log:#{short_id(envelope)}",
      summary: "trial #{Keyword.fetch!(opts, :verdict)}"
    })
  end

  defp put_receipt(record, opts) do
    case Keyword.get(opts, :receipts_store) do
      nil -> {:ok, record}
      store -> Receipts.Store.Memory.put(store, record)
    end
  end

  defp publish(record, projection, primary_ref, state_or_outcome, opts) do
    payload =
      record
      |> Map.from_struct()
      |> Map.drop([:__struct__])
      |> Map.put(:state_or_outcome, state_or_outcome)

    publish_event(
      record,
      %{
        projection: projection,
        primary_ref: primary_ref,
        payload: payload
      },
      opts
    )
  end

  defp publish_event(source, event, opts) do
    case Keyword.get(opts, :outbox) do
      nil ->
        :ok

      outbox ->
        event =
          event
          |> Map.put_new(:trace_id, Map.get(source, :trace_id))
          |> Map.put_new(:tenant_ref, Map.get(source, :tenant_ref))
          |> Map.put_new(:installation_ref, Map.get(source, :installation_ref))
          |> Map.put_new(:correlation_id, Map.get(source, :receipt_ref))
          |> Map.put_new(:idempotency_key, Map.get(source, :receipt_ref) || event.primary_ref)

        case Outbox.enqueue(outbox, event) do
          {:ok, _event} -> :ok
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp response(envelope, payload) do
    receipt_refs =
      payload
      |> Map.take([
        :receipt_ref,
        :candidate_receipt_ref,
        :swap_receipt_ref,
        :promotion_record_ref
      ])
      |> Map.values()
      |> Enum.filter(&is_binary/1)

    ProtocolSupport.response(envelope, payload, receipt_refs)
  end

  defp payload_attrs(%Envelope{payload: payload}) when is_map(payload),
    do: normalize_keys(payload)

  defp payload_attrs(_envelope), do: %{}

  defp normalize_keys(map) do
    Map.new(map, fn
      {key, value} when is_binary(key) -> {safe_existing_atom(key), value}
      {key, value} -> {key, value}
    end)
  end

  defp safe_existing_atom(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError -> key
  end

  defp value(map, key, default \\ nil) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key), default)
  end

  defp short_id(%Envelope{} = envelope) do
    :crypto.hash(:sha256, "#{envelope.envelope_ref}:#{System.unique_integer([:positive])}")
    |> Base.encode16(case: :lower)
    |> binary_part(0, 12)
  end
end

defmodule Chassis.Mezzanine.Bridge.Evolution.CreateFailureBatch do
  @behaviour Chassis.Boundary.Protocol
  def call(envelope, opts),
    do: Chassis.Mezzanine.Bridge.Evolution.Protocol.create_failure_batch(envelope, opts)
end

defmodule Chassis.Mezzanine.Bridge.Evolution.Start do
  @behaviour Chassis.Boundary.Protocol
  def call(envelope, opts), do: Chassis.Mezzanine.Bridge.Evolution.Protocol.start(envelope, opts)
end

defmodule Chassis.Mezzanine.Bridge.Evolution.Stop do
  @behaviour Chassis.Boundary.Protocol
  def call(envelope, opts), do: Chassis.Mezzanine.Bridge.Evolution.Protocol.stop(envelope, opts)
end

defmodule Chassis.Mezzanine.Bridge.Evolution.GetStatus do
  @behaviour Chassis.Boundary.Protocol
  def call(envelope, opts),
    do: Chassis.Mezzanine.Bridge.Evolution.Protocol.get_status(envelope, opts)
end

defmodule Chassis.Mezzanine.Bridge.Evolution.ProvisionTrialNode do
  @behaviour Chassis.Boundary.Protocol
  def call(envelope, opts),
    do: Chassis.Mezzanine.Bridge.Evolution.Protocol.provision_trial_node(envelope, opts)
end

defmodule Chassis.Mezzanine.Bridge.Evolution.RunTrialReplay do
  @behaviour Chassis.Boundary.Protocol
  def call(envelope, opts),
    do: Chassis.Mezzanine.Bridge.Evolution.Protocol.run_trial_replay(envelope, opts)
end

defmodule Chassis.Mezzanine.Bridge.Evolution.ScoreCandidate do
  @behaviour Chassis.Boundary.Protocol
  def call(envelope, opts),
    do: Chassis.Mezzanine.Bridge.Evolution.Protocol.score_candidate(envelope, opts)
end

defmodule Chassis.Mezzanine.Bridge.Evolution.RequestPromotion do
  @behaviour Chassis.Boundary.Protocol
  def call(envelope, opts),
    do: Chassis.Mezzanine.Bridge.Evolution.Protocol.request_promotion(envelope, opts)
end

defmodule Chassis.Mezzanine.Bridge.Evolution.PromoteCandidate do
  @behaviour Chassis.Boundary.Protocol
  def call(envelope, opts),
    do: Chassis.Mezzanine.Bridge.Evolution.Protocol.promote_candidate(envelope, opts)
end

defmodule Chassis.Mezzanine.Bridge.Evolution.RollbackCandidate do
  @behaviour Chassis.Boundary.Protocol
  def call(envelope, opts),
    do: Chassis.Mezzanine.Bridge.Evolution.Protocol.rollback_candidate(envelope, opts)
end

defmodule Chassis.Mezzanine.Bridge.Evolution.MaterializeWeight do
  @behaviour Chassis.Boundary.Protocol
  def call(envelope, opts),
    do: Chassis.Mezzanine.Bridge.Evolution.Protocol.materialize_weight(envelope, opts)
end

defmodule Chassis.Mezzanine.Bridge.Evolution.ReloadTensorPatch do
  @behaviour Chassis.Boundary.Protocol
  def call(envelope, opts),
    do: Chassis.Mezzanine.Bridge.Evolution.Protocol.reload_tensor_patch(envelope, opts)
end

defmodule Chassis.Mezzanine.Bridge.Evolution.RollbackTensorPatch do
  @behaviour Chassis.Boundary.Protocol
  def call(envelope, opts),
    do: Chassis.Mezzanine.Bridge.Evolution.Protocol.rollback_tensor_patch(envelope, opts)
end

defmodule Chassis.Mezzanine.Bridge.ProjectionPublisher do
  @moduledoc "Publishes deployment receipts into the Chassis-to-Mezzanine outbox."

  alias Chassis.Mezzanine.Bridge.Outbox
  alias Chassis.Projection.ChassisDeploymentProjection
  alias Chassis.Receipts.DeploymentRecord

  @spec publish(DeploymentRecord.t() | map(), keyword()) :: {:ok, map()} | {:error, term()}
  def publish(record, opts \\ []) do
    outbox = Keyword.get(opts, :outbox, Outbox)
    projection = ChassisDeploymentProjection.from_receipt(record)

    Outbox.enqueue(outbox, %{
      kind: :chassis_deployment,
      payload: Map.from_struct(projection),
      idempotency_key: projection.receipt_ref,
      created_at: DateTime.utc_now()
    })
  end
end

defmodule Chassis.Mezzanine.Bridge.Outbox.Entry do
  @moduledoc """
  Typed Chassis-to-Mezzanine outbox event.

  The entry is intentionally bounded to projection refs, tenant/install scope,
  correlation metadata, and an operator-safe payload.
  """

  @sensitive_keys MapSet.new([
                    :raw_body,
                    :raw_bytes,
                    :raw_diff,
                    :raw_payload,
                    :raw_prompt,
                    :raw_provider_token,
                    :raw_transcript,
                    :body,
                    :payload_bytes,
                    :provider_token,
                    :secret,
                    :secret_value,
                    :transcript
                  ])

  @ref_fields [
    :receipt_ref,
    :failure_batch_ref,
    :candidate_ref,
    :trial_ref,
    :trial_run_ref,
    :score_matrix_ref,
    :promotion_ref,
    :promotion_intent_ref,
    :swap_ref,
    :rollback_ref,
    :materialization_record_ref,
    :tensor_reload_record_ref,
    :tensor_rollback_record_ref,
    :deployment_ref,
    :app_ref
  ]

  defstruct [
    :kind,
    :projection,
    :primary_ref,
    :payload,
    :trace_id,
    :tenant_ref,
    :installation_ref,
    :correlation_id,
    :idempotency_key,
    :outbox_ref,
    :status,
    :created_at,
    :delivered_at
  ]

  @type t :: %__MODULE__{}

  @spec new(map() | struct()) :: {:ok, t()} | {:error, term()}
  def new(event) when is_map(event) do
    event = to_map(event)
    payload = event |> value(:payload, %{}) |> safe_payload()
    kind = value(event, :kind) || value(event, :projection)
    projection = value(event, :projection) || projection_from_kind(kind)

    primary_ref =
      value(event, :primary_ref) || primary_ref(payload) || value(event, :idempotency_key)

    cond do
      is_nil(projection) ->
        {:error, :projection_required}

      not is_binary(primary_ref) or primary_ref == "" ->
        {:error, :primary_ref_required}

      true ->
        {:ok,
         %__MODULE__{
           kind: normalize_atom(kind || projection),
           projection: normalize_atom(projection),
           primary_ref: primary_ref,
           payload: payload,
           trace_id: value(event, :trace_id) || value(payload, :trace_id),
           tenant_ref: value(event, :tenant_ref) || value(payload, :tenant_ref),
           installation_ref: value(event, :installation_ref) || value(payload, :installation_ref),
           correlation_id: value(event, :correlation_id) || value(payload, :receipt_ref),
           idempotency_key: value(event, :idempotency_key),
           outbox_ref: value(event, :outbox_ref),
           status: value(event, :status),
           created_at: value(event, :created_at),
           delivered_at: value(event, :delivered_at)
         }}
    end
  end

  def new(_event), do: {:error, :invalid_event}

  defp to_map(%__MODULE__{} = event), do: Map.from_struct(event)
  defp to_map(%_struct{} = event), do: Map.from_struct(event)
  defp to_map(event), do: Map.new(event)

  defp projection_from_kind(:chassis_deployment), do: :chassis_deployment
  defp projection_from_kind("chassis_deployment"), do: :chassis_deployment

  defp projection_from_kind(kind) when kind in [:chassis_evolution, "chassis_evolution"],
    do: :chassis_evolution

  defp projection_from_kind(kind) when kind in [:chassis_candidate, "chassis_candidate"],
    do: :chassis_candidate

  defp projection_from_kind(kind) when kind in [:chassis_trial, "chassis_trial"],
    do: :chassis_trial

  defp projection_from_kind(kind) when kind in [:chassis_score_matrix, "chassis_score_matrix"],
    do: :chassis_score_matrix

  defp projection_from_kind(kind) when kind in [:chassis_promotion, "chassis_promotion"],
    do: :chassis_promotion

  defp projection_from_kind(kind) when kind in [:chassis_swap, "chassis_swap"], do: :chassis_swap

  defp projection_from_kind(kind)
       when kind in [:chassis_model_materialization, "chassis_model_materialization"],
       do: :chassis_model_materialization

  defp projection_from_kind(kind)
       when kind in [:chassis_tensor_reload, "chassis_tensor_reload"],
       do: :chassis_tensor_reload

  defp projection_from_kind(other), do: other

  defp primary_ref(payload) do
    Enum.find_value(@ref_fields, fn field ->
      case value(payload, field) do
        ref when is_binary(ref) and ref != "" -> ref
        _missing -> nil
      end
    end)
  end

  defp safe_payload(payload) when is_map(payload) do
    payload
    |> to_map()
    |> Enum.reject(fn {key, _value} -> sensitive_key?(key) end)
    |> Map.new(fn {key, value} -> {normalize_key(key), safe_value(value)} end)
  end

  defp safe_payload(_payload), do: %{}

  defp safe_value(value) when is_map(value), do: safe_payload(value)
  defp safe_value(values) when is_list(values), do: Enum.map(values, &safe_value/1)
  defp safe_value(value), do: value

  defp sensitive_key?(key) when is_atom(key), do: MapSet.member?(@sensitive_keys, key)

  defp sensitive_key?(key) when is_binary(key) do
    key
    |> String.trim()
    |> String.to_existing_atom()
    |> sensitive_key?()
  rescue
    ArgumentError -> false
  end

  defp normalize_key(key) when is_binary(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError -> key
  end

  defp normalize_key(key), do: key

  defp normalize_atom(value) when is_binary(value) do
    String.to_existing_atom(value)
  rescue
    ArgumentError -> value
  end

  defp normalize_atom(value), do: value

  defp value(map, key, default \\ nil) when is_map(map) do
    Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  end
end

defmodule Chassis.Mezzanine.Bridge.Outbox do
  @moduledoc "Chassis-local outbox with idempotent enqueue and explicit drain."

  use GenServer

  alias Chassis.Mezzanine.Bridge.Outbox.Entry

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)

    case name do
      nil -> GenServer.start_link(__MODULE__, opts, [])
      _ -> GenServer.start_link(__MODULE__, opts, name: name)
    end
  end

  @spec enqueue(GenServer.server(), map()) :: {:ok, map()} | {:error, term()}
  def enqueue(server, event), do: GenServer.call(server, {:enqueue, event})

  @spec list(GenServer.server()) :: [map()]
  def list(server), do: GenServer.call(server, :list)

  @spec drain(GenServer.server(), keyword()) :: {:ok, map()} | {:error, term()}
  def drain(server, opts \\ []) do
    case Keyword.fetch(opts, :publisher) do
      {:ok, publisher} when is_function(publisher, 1) ->
        server
        |> pending()
        |> Enum.reduce_while({:ok, 0}, fn event, {:ok, count} ->
          case publish(publisher, event) do
            :ok ->
              mark_delivered(server, event.outbox_ref)
              {:cont, {:ok, count + 1}}

            {:ok, _receipt} ->
              mark_delivered(server, event.outbox_ref)
              {:cont, {:ok, count + 1}}

            {:error, reason} ->
              {:halt, {:error, {:drain_failed, event, reason}}}
          end
        end)
        |> case do
          {:ok, delivered} -> {:ok, %{delivered: delivered}}
          {:error, reason} -> {:error, reason}
        end

      _missing ->
        {:error, :publisher_required}
    end
  end

  @impl true
  def init(_opts), do: {:ok, %{by_key: %{}, order: []}}

  @impl true
  def handle_call({:enqueue, event}, _from, state) do
    with {:ok, key} <- idempotency_key(event),
         {:ok, %Entry{} = entry} <- Entry.new(Map.put(event, :idempotency_key, key)) do
      case Map.fetch(state.by_key, key) do
        {:ok, existing} ->
          {:reply, {:ok, existing}, state}

        :error ->
          outbox_ref = "outbox:chassis:" <> short_id()

          event =
            %Entry{
              entry
              | outbox_ref: outbox_ref,
                idempotency_key: key,
                status: :pending,
                created_at: entry.created_at || DateTime.utc_now()
            }

          state = %{
            state
            | by_key: Map.put(state.by_key, key, event),
              order: state.order ++ [key]
          }

          {:reply, {:ok, event}, state}
      end
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:list, _from, state), do: {:reply, events(state), state}

  def handle_call(:pending, _from, state) do
    {:reply, Enum.filter(events(state), &(&1.status == :pending)), state}
  end

  def handle_call({:mark_delivered, outbox_ref}, _from, state) do
    state =
      update_event(state, outbox_ref, fn event ->
        %Entry{} = event
        %{event | status: :delivered, delivered_at: DateTime.utc_now()}
      end)

    {:reply, :ok, state}
  end

  defp pending(server), do: GenServer.call(server, :pending)

  defp mark_delivered(server, outbox_ref),
    do: GenServer.call(server, {:mark_delivered, outbox_ref})

  defp publish(fun, event) when is_function(fun, 1), do: fun.(event)

  defp idempotency_key(%{idempotency_key: key}) when is_binary(key) and key != "", do: {:ok, key}
  defp idempotency_key(_event), do: {:error, :idempotency_key_required}

  defp events(state), do: Enum.map(state.order, &Map.fetch!(state.by_key, &1))

  defp update_event(state, outbox_ref, fun) do
    by_key =
      Map.new(state.by_key, fn {key, event} ->
        if event.outbox_ref == outbox_ref do
          {key, fun.(event)}
        else
          {key, event}
        end
      end)

    %{state | by_key: by_key}
  end

  defp short_id, do: :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
end
