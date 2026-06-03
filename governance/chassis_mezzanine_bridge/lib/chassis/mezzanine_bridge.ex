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
          |> Map.put(:payload, request)
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

defmodule Chassis.Mezzanine.Bridge.Outbox do
  @moduledoc "Chassis-local outbox with idempotent enqueue and explicit drain."

  use GenServer

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
    with {:ok, key} <- idempotency_key(event) do
      case Map.fetch(state.by_key, key) do
        {:ok, existing} ->
          {:reply, {:ok, existing}, state}

        :error ->
          outbox_ref = "outbox:chassis:" <> short_id()

          event =
            event
            |> Map.put(:outbox_ref, outbox_ref)
            |> Map.put(:idempotency_key, key)
            |> Map.put(:status, :pending)
            |> Map.put_new(:created_at, DateTime.utc_now())

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
        event
        |> Map.put(:status, :delivered)
        |> Map.put(:delivered_at, DateTime.utc_now())
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
