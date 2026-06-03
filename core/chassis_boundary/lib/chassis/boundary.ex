defmodule Chassis.Boundary.Protocol do
  @moduledoc "Ring 0 boundary protocol behaviour."

  alias Chassis.Boundary.{Envelope, Error}

  @type request :: struct() | map()
  @type response :: struct() | map()
  @type opts :: keyword()

  @callback call(request_envelope :: Envelope.t(request()), opts()) ::
              {:ok, Envelope.t(response())} | {:error, Error.t()}
end

defmodule Chassis.Boundary.Error do
  @moduledoc "Bounded error taxonomy for Chassis Ring 0 boundaries."

  @derive {Inspect,
           only: [
             :error_ref,
             :code,
             :retry_posture,
             :safe_message,
             :redaction,
             :trace_id,
             :protocol_ref
           ]}
  defstruct [
    :error_ref,
    :code,
    :retry_posture,
    :safe_message,
    :redaction,
    :trace_id,
    :protocol_ref
  ]

  @type code ::
          :authority_denied
          | :tenant_context_required
          | :idempotency_key_required
          | :invalid_request
          | :missing_tenant
          | :residency_violation
          | :quota_exceeded
          | :topology_invalid
          | :host_unreachable
          | :secret_unavailable
          | :provisioning_failed
          | :mesh_join_failed
          | :stale_revision
          | :dependency_unavailable
          | :timeout
          | :conflict
          | :retry_later
          | :non_retryable_failure

  @type retry_posture :: :retryable | :non_retryable | :operator_required
  @type redaction :: :safe | :sensitive | :secret

  @type t :: %__MODULE__{
          error_ref: String.t(),
          code: code(),
          retry_posture: retry_posture(),
          safe_message: String.t(),
          redaction: redaction(),
          trace_id: String.t() | nil,
          protocol_ref: String.t() | nil
        }

  @spec new(code(), Chassis.Boundary.Envelope.t() | map() | keyword()) :: t()
  def new(code, envelope_or_opts \\ [], opts \\ [])

  def new(code, envelope, opts) when is_struct(envelope, Chassis.Boundary.Envelope) do
    new(
      code,
      [
        trace_id: Map.get(envelope, :trace_id),
        protocol_ref: Map.get(envelope, :protocol_ref)
      ],
      opts
    )
  end

  def new(code, attrs, opts) when is_map(attrs) do
    new(code, Map.to_list(attrs), opts)
  end

  def new(code, attrs, opts) when is_list(attrs) do
    merged = Keyword.merge(attrs, opts)

    %__MODULE__{
      error_ref: Keyword.get(merged, :error_ref, "err:" <> random_ref()),
      code: code,
      retry_posture: Keyword.get(merged, :retry_posture, default_retry_posture(code)),
      safe_message: Keyword.get(merged, :safe_message, default_message(code)),
      redaction: Keyword.get(merged, :redaction, :safe),
      trace_id: Keyword.get(merged, :trace_id),
      protocol_ref: Keyword.get(merged, :protocol_ref)
    }
  end

  defp default_retry_posture(:dependency_unavailable), do: :retryable
  defp default_retry_posture(:timeout), do: :retryable
  defp default_retry_posture(:retry_later), do: :retryable
  defp default_retry_posture(:authority_denied), do: :operator_required
  defp default_retry_posture(:tenant_context_required), do: :operator_required
  defp default_retry_posture(:quota_exceeded), do: :operator_required
  defp default_retry_posture(_code), do: :non_retryable

  defp default_message(:authority_denied), do: "Boundary authority denied the request"
  defp default_message(:tenant_context_required), do: "Tenant context is required"
  defp default_message(:idempotency_key_required), do: "Idempotency key is required"
  defp default_message(:invalid_request), do: "Boundary request is invalid"
  defp default_message(:missing_tenant), do: "Tenant context is missing"
  defp default_message(:dependency_unavailable), do: "Boundary dependency is unavailable"
  defp default_message(:non_retryable_failure), do: "Boundary request failed"
  defp default_message(code), do: code |> Atom.to_string() |> String.replace("_", " ")

  defp random_ref, do: :crypto.strong_rand_bytes(12) |> Base.encode16(case: :lower)
end

defmodule Chassis.Boundary.Envelope do
  @moduledoc "Canonical Ring 0 envelope wrapping a request or response payload."

  alias GroundPlane.Boundary.Codec

  defstruct [
    :protocol_ref,
    :envelope_ref,
    :tenant_ref,
    :installation_ref,
    :actor_ref,
    :system_actor_ref,
    :authority_ref,
    :idempotency_key,
    :trace_id,
    :correlation_id,
    :issued_at,
    :payload,
    :status,
    receipt_refs: []
  ]

  @type t :: t(struct() | map())

  @type t(payload) :: %__MODULE__{
          protocol_ref: String.t(),
          envelope_ref: String.t(),
          tenant_ref: String.t() | nil,
          installation_ref: String.t() | nil,
          actor_ref: String.t() | nil,
          system_actor_ref: String.t() | nil,
          authority_ref: String.t() | nil,
          idempotency_key: String.t() | nil,
          trace_id: String.t(),
          correlation_id: String.t() | nil,
          issued_at: DateTime.t(),
          payload: payload,
          status: :request | :accepted | :ok | :denied | :failed | :deferred,
          receipt_refs: [String.t()]
        }

  @fields [
    :protocol_ref,
    :envelope_ref,
    :tenant_ref,
    :installation_ref,
    :actor_ref,
    :system_actor_ref,
    :authority_ref,
    :idempotency_key,
    :trace_id,
    :correlation_id,
    :issued_at,
    :payload,
    :status,
    :receipt_refs
  ]

  @string_fields MapSet.new([
                   :protocol_ref,
                   :envelope_ref,
                   :tenant_ref,
                   :installation_ref,
                   :actor_ref,
                   :system_actor_ref,
                   :authority_ref,
                   :idempotency_key,
                   :trace_id,
                   :correlation_id
                 ])

  @statuses MapSet.new([:request, :accepted, :ok, :denied, :failed, :deferred])

  @payload_atoms MapSet.new([
                   :active,
                   :accepted,
                   :chassis_local,
                   :deferred,
                   :denied,
                   :dev,
                   :draining,
                   :failed,
                   :inactive,
                   :local,
                   :ok,
                   :partial,
                   :prod,
                   :request
                 ])

  @spec new!(map() | keyword()) :: t()
  def new!(attrs) when is_list(attrs) or is_map(attrs) do
    normalized =
      attrs
      |> Map.new()
      |> normalize_keys()
      |> normalize_status()
      |> normalize_issued_at()
      |> normalize_receipt_refs()

    envelope = struct!(__MODULE__, Map.take(normalized, @fields))
    validate!(envelope)
    envelope
  end

  @spec response!(t(), struct() | map(), keyword()) :: t()
  def response!(%__MODULE__{} = request, payload, opts \\ []) do
    receipt_refs = Keyword.get(opts, :receipt_refs, receipt_refs(payload))

    new!(%{
      protocol_ref: request.protocol_ref,
      envelope_ref: Keyword.get(opts, :envelope_ref, "env:response:" <> request.envelope_ref),
      tenant_ref: request.tenant_ref,
      installation_ref: request.installation_ref,
      actor_ref: request.actor_ref,
      system_actor_ref: request.system_actor_ref,
      authority_ref: request.authority_ref,
      idempotency_key: request.idempotency_key,
      trace_id: request.trace_id,
      correlation_id: request.correlation_id || request.envelope_ref,
      issued_at: Keyword.get(opts, :issued_at, request.issued_at),
      payload: payload,
      status: Keyword.get(opts, :status, payload_status(payload)),
      receipt_refs: receipt_refs
    })
  end

  @spec encode!(t()) :: String.t()
  def encode!(%__MODULE__{} = envelope) do
    envelope
    |> chassis_pre_validate!()
    |> to_codec_map()
    |> Codec.encode!()
  end

  @spec decode!(String.t()) :: map()
  def decode!(encoded), do: Codec.decode!(encoded)

  @spec digest(t()) :: String.t()
  def digest(%__MODULE__{} = envelope) do
    envelope
    |> chassis_pre_validate!()
    |> to_codec_map()
    |> Codec.digest()
  end

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = envelope), do: to_codec_map(envelope)

  defp normalize_keys(attrs) do
    Enum.reduce(attrs, %{}, fn {key, value}, acc ->
      field = normalize_key(key)

      if field in @fields do
        Map.put(acc, field, value)
      else
        raise ArgumentError, "unknown boundary envelope field #{inspect(key)}"
      end
    end)
  end

  defp normalize_key(key) when is_atom(key), do: key

  defp normalize_key(key) when is_binary(key) do
    Enum.find(@fields, fn field -> Atom.to_string(field) == key end) ||
      raise ArgumentError, "unknown boundary envelope field #{inspect(key)}"
  end

  defp normalize_key(key),
    do: raise(ArgumentError, "unsupported boundary envelope key #{inspect(key)}")

  defp normalize_status(%{status: status} = attrs),
    do: %{attrs | status: normalize_status_value(status)}

  defp normalize_status(attrs), do: Map.put(attrs, :status, :request)

  defp normalize_status_value(status)
       when status in [:request, :accepted, :ok, :denied, :failed, :deferred],
       do: status

  defp normalize_status_value(status) when is_binary(status) do
    case status do
      "request" -> :request
      "accepted" -> :accepted
      "ok" -> :ok
      "denied" -> :denied
      "failed" -> :failed
      "deferred" -> :deferred
      _ -> raise ArgumentError, "unsupported boundary envelope status #{inspect(status)}"
    end
  end

  defp normalize_status_value(status),
    do: raise(ArgumentError, "unsupported boundary envelope status #{inspect(status)}")

  defp normalize_issued_at(%{issued_at: %DateTime{}} = attrs), do: attrs

  defp normalize_issued_at(%{issued_at: issued_at} = attrs) when is_binary(issued_at) do
    case DateTime.from_iso8601(issued_at) do
      {:ok, datetime, _offset} -> %{attrs | issued_at: datetime}
      {:error, reason} -> raise ArgumentError, "invalid issued_at #{inspect(reason)}"
    end
  end

  defp normalize_issued_at(attrs), do: Map.put(attrs, :issued_at, DateTime.utc_now())

  defp normalize_receipt_refs(%{receipt_refs: refs} = attrs) when is_list(refs), do: attrs

  defp normalize_receipt_refs(%{receipt_refs: refs}),
    do: raise(ArgumentError, "receipt_refs must be a list, got #{inspect(refs)}")

  defp normalize_receipt_refs(attrs), do: Map.put(attrs, :receipt_refs, [])

  defp validate!(%__MODULE__{} = envelope) do
    [:protocol_ref, :envelope_ref, :trace_id]
    |> Enum.each(&require_binary!(envelope, &1))

    if is_nil(envelope.payload), do: raise(ArgumentError, "payload required")

    unless MapSet.member?(@statuses, envelope.status) do
      raise ArgumentError, "status must be one of #{inspect(MapSet.to_list(@statuses))}"
    end

    validate_string_fields!(envelope)
    validate_policy_required_fields!(envelope)
    :ok
  end

  defp validate_string_fields!(%__MODULE__{} = envelope) do
    Enum.each(@string_fields, fn field ->
      case Map.get(envelope, field) do
        nil -> :ok
        value when is_binary(value) and value != "" -> :ok
        value -> raise ArgumentError, "#{field} must be a non-empty string, got #{inspect(value)}"
      end
    end)

    Enum.each(envelope.receipt_refs, fn
      ref when is_binary(ref) and ref != "" ->
        :ok

      ref ->
        raise ArgumentError, "receipt_refs must contain non-empty strings, got #{inspect(ref)}"
    end)
  end

  defp validate_policy_required_fields!(%__MODULE__{} = envelope) do
    case Chassis.Boundary.Registry.spec(envelope.protocol_ref) do
      {:ok, spec} ->
        if spec.mutation?, do: require_binary!(envelope, :tenant_ref)
        if spec.authority_required?, do: require_binary!(envelope, :authority_ref)
        if spec.idempotency_required?, do: require_binary!(envelope, :idempotency_key)
        if spec.trace_required?, do: require_binary!(envelope, :trace_id)

      :error ->
        :ok
    end
  end

  defp require_binary!(envelope, field) do
    case Map.get(envelope, field) do
      value when is_binary(value) and value != "" -> :ok
      _value -> raise ArgumentError, "#{field} required"
    end
  end

  defp chassis_pre_validate!(%__MODULE__{} = envelope) do
    payload = envelope.payload || %{}

    cond do
      has_secret_lease?(payload) ->
        raise ArgumentError,
              "SecretLease must never appear in boundary payload (envelope=#{envelope.envelope_ref})"

      has_raw_key_bytes?(payload) ->
        raise ArgumentError, "raw private key bytes must never appear in boundary payload"

      true ->
        reject_unsafe_atoms!(payload)
        envelope
    end
  end

  defp has_secret_lease?(payload) do
    Enum.any?(extract_values(payload), &is_struct(&1, Chassis.Secrets.SecretLease))
  end

  defp has_raw_key_bytes?(payload) do
    Enum.any?(extract_values(payload), fn
      value when is_binary(value) ->
        String.match?(value, ~r/-----BEGIN [A-Z ]*PRIVATE KEY-----/)

      _other ->
        false
    end)
  end

  defp reject_unsafe_atoms!(payload) do
    payload
    |> extract_payload_values()
    |> Enum.each(fn
      atom when is_atom(atom) and not is_nil(atom) ->
        unless MapSet.member?(@payload_atoms, atom) do
          raise ArgumentError, "unsafe_atom #{inspect(atom)} must not appear in boundary payload"
        end

      _other ->
        :ok
    end)
  end

  defp extract_payload_values(value) when is_struct(value) do
    value
    |> Map.from_struct()
    |> extract_payload_values()
  end

  defp extract_payload_values(value) when is_map(value) do
    Enum.flat_map(value, fn {_key, nested} -> [nested | extract_payload_values(nested)] end)
  end

  defp extract_payload_values(value) when is_list(value),
    do: Enum.flat_map(value, &extract_payload_values/1)

  defp extract_payload_values(value), do: [value]

  defp extract_values(value) when is_struct(value) do
    value
    |> Map.from_struct()
    |> extract_values()
  end

  defp extract_values(value) when is_map(value) do
    Enum.flat_map(value, fn {key, nested} -> [key, nested | extract_values(nested)] end)
  end

  defp extract_values(value) when is_list(value), do: Enum.flat_map(value, &extract_values/1)
  defp extract_values(value), do: [value]

  defp to_codec_map(%__MODULE__{} = envelope) do
    %{
      protocol_ref: envelope.protocol_ref,
      envelope_ref: envelope.envelope_ref,
      tenant_ref: envelope.tenant_ref,
      installation_ref: envelope.installation_ref,
      actor_ref: envelope.actor_ref,
      system_actor_ref: envelope.system_actor_ref,
      authority_ref: envelope.authority_ref,
      idempotency_key: envelope.idempotency_key,
      trace_id: envelope.trace_id,
      correlation_id: envelope.correlation_id,
      issued_at: DateTime.to_iso8601(envelope.issued_at),
      payload: to_codec_value(envelope.payload),
      status: Atom.to_string(envelope.status),
      receipt_refs: envelope.receipt_refs
    }
  end

  defp to_codec_value(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
  defp to_codec_value(%NaiveDateTime{} = datetime), do: NaiveDateTime.to_iso8601(datetime)
  defp to_codec_value(atom) when is_atom(atom) and not is_nil(atom), do: Atom.to_string(atom)

  defp to_codec_value(value) when is_struct(value) do
    value
    |> Map.from_struct()
    |> to_codec_value()
  end

  defp to_codec_value(value) when is_map(value) do
    Enum.reduce(value, %{}, fn {key, nested}, acc ->
      canonical_key = to_codec_key(key)

      if Map.has_key?(acc, canonical_key) do
        raise ArgumentError, "ambiguous boundary payload key #{inspect(canonical_key)}"
      end

      Map.put(acc, canonical_key, to_codec_value(nested))
    end)
  end

  defp to_codec_value(values) when is_list(values), do: Enum.map(values, &to_codec_value/1)
  defp to_codec_value(value), do: value

  defp to_codec_key(key) when is_atom(key), do: Atom.to_string(key)
  defp to_codec_key(key) when is_binary(key) and key != "", do: key

  defp to_codec_key(key),
    do: raise(ArgumentError, "unsupported boundary payload key #{inspect(key)}")

  defp receipt_refs(payload) when is_struct(payload),
    do: payload |> Map.from_struct() |> receipt_refs()

  defp receipt_refs(payload) when is_map(payload) do
    [:deployment_receipt_ref, :rollback_receipt_ref, :provisioning_receipt_ref, :receipt_ref]
    |> Enum.flat_map(fn key ->
      case Map.get(payload, key) || Map.get(payload, Atom.to_string(key)) do
        value when is_binary(value) and value != "" -> [value]
        _other -> []
      end
    end)
    |> Enum.uniq()
  end

  defp receipt_refs(_payload), do: []

  defp payload_status(payload) when is_struct(payload),
    do: payload |> Map.from_struct() |> payload_status()

  defp payload_status(payload) when is_map(payload) do
    case Map.get(payload, :status) || Map.get(payload, "status") do
      status when status in [:accepted, :ok, :denied, :failed, :deferred] -> status
      status when is_binary(status) -> normalize_status_value(status)
      _other -> :ok
    end
  end

  defp payload_status(_payload), do: :ok
end

defmodule Chassis.Boundary.LocalAdapter do
  @moduledoc "Direct in-process function dispatch for Ring 0 protocols."

  alias Chassis.Boundary.{Envelope, Error, Registry}

  @spec dispatch(Envelope.t(), keyword()) :: {:ok, Envelope.t()} | {:error, Error.t()}
  def dispatch(%Envelope{protocol_ref: protocol_ref} = envelope, opts \\ []) do
    with {:ok, spec} <- Registry.spec(protocol_ref),
         {:ok, module} <- protocol_module(spec, opts),
         :ok <- ensure_callable(module),
         :ok <- validate_request(envelope) do
      call(module, envelope, opts)
    else
      :error ->
        {:error,
         Error.new(:invalid_request, envelope,
           safe_message: "No boundary protocol registered for #{protocol_ref}"
         )}

      {:error, %Error{} = error} ->
        {:error, error}
    end
  end

  defp protocol_module(spec, opts) do
    case Keyword.get(opts, :protocol_module) do
      nil -> registered_local_module(spec)
      module when is_atom(module) -> {:ok, module}
    end
  end

  defp registered_local_module(%{adapters: %{local: nil}}),
    do:
      {:error,
       Error.new(:invalid_request, safe_message: "No local adapter registered for protocol")}

  defp registered_local_module(%{adapters: %{local: module}}) when is_atom(module),
    do: {:ok, module}

  defp ensure_callable(module) do
    if Code.ensure_loaded?(module) and function_exported?(module, :call, 2) do
      :ok
    else
      {:error,
       Error.new(:invalid_request,
         safe_message: "Local adapter module #{inspect(module)} does not implement call/2"
       )}
    end
  end

  defp validate_request(%Envelope{} = envelope) do
    _encoded = Envelope.encode!(envelope)
    :ok
  rescue
    exception in ArgumentError ->
      {:error,
       Error.new(:invalid_request, envelope,
         safe_message: Exception.message(exception),
         redaction: :safe
       )}
  end

  defp call(module, envelope, opts) do
    case module.call(envelope, opts) do
      {:ok, %Envelope{} = response} ->
        _encoded = Envelope.encode!(response)
        {:ok, response}

      {:error, %Error{} = error} ->
        {:error, error}

      other ->
        {:error,
         Error.new(:invalid_request, envelope,
           safe_message: "Local adapter returned invalid boundary result #{inspect(other)}"
         )}
    end
  rescue
    _exception ->
      {:error,
       Error.new(:non_retryable_failure, envelope,
         safe_message: "Local adapter raised an exception",
         retry_posture: :non_retryable,
         redaction: :safe
       )}
  end
end

defmodule Chassis.Boundary.BeamDistributionAdapter do
  @moduledoc "Distributed Erlang dispatch for Ring 0 protocols."

  alias Chassis.Boundary.{Envelope, Error, LocalAdapter}

  @spec dispatch(node(), Envelope.t(), keyword()) :: {:ok, Envelope.t()} | {:error, Error.t()}
  def dispatch(target_node, %Envelope{} = envelope, opts \\ []) when is_atom(target_node) do
    encoded = Envelope.encode!(envelope)
    timeout = Keyword.get(opts, :rpc_timeout, 30_000)

    case :rpc.call(target_node, __MODULE__, :__remote_dispatch__, [encoded, opts], timeout) do
      {:badrpc, reason} ->
        {:error,
         Error.new(:dependency_unavailable, envelope,
           retry_posture: :retryable,
           safe_message: "RPC to remote node failed: #{inspect(reason)}"
         )}

      result ->
        result
    end
  rescue
    exception in ArgumentError ->
      {:error,
       Error.new(:invalid_request, envelope,
         safe_message: Exception.message(exception),
         redaction: :safe
       )}
  end

  @doc false
  @spec __remote_dispatch__(String.t(), keyword()) :: {:ok, Envelope.t()} | {:error, Error.t()}
  def __remote_dispatch__(encoded, opts) do
    encoded
    |> Envelope.decode!()
    |> Envelope.new!()
    |> LocalAdapter.dispatch(opts)
  rescue
    exception in ArgumentError ->
      {:error,
       Error.new(:invalid_request,
         safe_message: Exception.message(exception),
         redaction: :safe
       )}
  end
end

defmodule Chassis.Boundary.UnixSocketAdapter do
  @moduledoc "Unix socket boundary adapter placeholder for the later host-daemon phase."

  alias Chassis.Boundary.{Envelope, Error}

  @spec dispatch(Envelope.t(), keyword()) :: {:error, Error.t()}
  def dispatch(%Envelope{} = envelope, _opts \\ []) do
    {:error,
     Error.new(:dependency_unavailable, envelope,
       retry_posture: :retryable,
       safe_message: "Unix socket boundary adapter is not configured in Phase 12"
     )}
  end
end

defmodule Chassis.Boundary do
  @moduledoc "Ring 0 boundary dispatcher."

  alias Chassis.Boundary.{BeamDistributionAdapter, Envelope, Error, LocalAdapter}

  @spec dispatch(Envelope.t(), keyword()) :: {:ok, Envelope.t()} | {:error, Error.t()}
  def dispatch(envelope_or_ref, opts_or_attrs \\ [])

  def dispatch(%Envelope{} = envelope, opts) do
    case Keyword.get(opts, :target_node, :local) do
      :local ->
        LocalAdapter.dispatch(envelope, opts)

      node when is_atom(node) ->
        BeamDistributionAdapter.dispatch(node, envelope, opts)

      other ->
        {:error,
         Error.new(:invalid_request, envelope,
           safe_message: "invalid target node #{inspect(other)}"
         )}
    end
  end

  @spec dispatch(String.t(), map()) :: {:ok, Envelope.t()} | {:error, Error.t()}
  def dispatch(protocol_ref, attrs) when is_binary(protocol_ref) and is_map(attrs) do
    attrs
    |> Map.put(:protocol_ref, protocol_ref)
    |> Envelope.new!()
    |> dispatch([])
  end
end

defmodule Chassis.Boundary.Registry do
  @moduledoc "Compile-time registry of Chassis Ring 0 boundary protocols."

  @type spec :: %{
          protocol_ref: String.t(),
          owner: atom(),
          consumer: atom(),
          request_module: module(),
          response_module: module(),
          error_module: module(),
          adapters: %{
            required(:local) => module() | nil,
            required(:beam_distribution) => module() | nil,
            required(:unix_socket) => module() | nil,
            required(:workflow_signal) => module() | nil,
            required(:external_http) => module() | nil
          },
          mutation?: boolean(),
          idempotency_required?: boolean(),
          authority_required?: boolean(),
          trace_required?: boolean(),
          codec: :canonical_map_v1
        }

  @adapter_keys [:local, :beam_distribution, :unix_socket, :workflow_signal, :external_http]

  @specs %{
    "boundary:mezzanine.chassis.materialize_deployment:v1" => %{
      protocol_ref: "boundary:mezzanine.chassis.materialize_deployment:v1",
      owner: :chassis,
      consumer: :mezzanine,
      request_module: Chassis.Boundary.MaterializeDeployment.Request,
      response_module: Chassis.Boundary.MaterializeDeployment.Response,
      error_module: Chassis.Boundary.MaterializeDeployment.Error,
      adapters: %{
        local: nil,
        beam_distribution: Chassis.Boundary.BeamDistributionAdapter,
        unix_socket: nil,
        workflow_signal: nil,
        external_http: nil
      },
      mutation?: true,
      idempotency_required?: true,
      authority_required?: true,
      trace_required?: true,
      codec: :canonical_map_v1
    },
    "boundary:mezzanine.chassis.rollback_deployment:v1" => %{
      protocol_ref: "boundary:mezzanine.chassis.rollback_deployment:v1",
      owner: :chassis,
      consumer: :mezzanine,
      request_module: Chassis.Boundary.RollbackDeployment.Request,
      response_module: Chassis.Boundary.RollbackDeployment.Response,
      error_module: Chassis.Boundary.RollbackDeployment.Error,
      adapters: %{
        local: nil,
        beam_distribution: Chassis.Boundary.BeamDistributionAdapter,
        unix_socket: nil,
        workflow_signal: nil,
        external_http: nil
      },
      mutation?: true,
      idempotency_required?: true,
      authority_required?: true,
      trace_required?: true,
      codec: :canonical_map_v1
    },
    "boundary:mezzanine.chassis.inspect_host:v1" => %{
      protocol_ref: "boundary:mezzanine.chassis.inspect_host:v1",
      owner: :chassis,
      consumer: :mezzanine,
      request_module: Chassis.Boundary.InspectHost.Request,
      response_module: Chassis.Boundary.InspectHost.Response,
      error_module: Chassis.Boundary.InspectHost.Error,
      adapters: %{
        local: nil,
        beam_distribution: Chassis.Boundary.BeamDistributionAdapter,
        unix_socket: nil,
        workflow_signal: nil,
        external_http: nil
      },
      mutation?: false,
      idempotency_required?: false,
      authority_required?: false,
      trace_required?: true,
      codec: :canonical_map_v1
    },
    "boundary:mezzanine.chassis.validate_topology:v1" => %{
      protocol_ref: "boundary:mezzanine.chassis.validate_topology:v1",
      owner: :chassis,
      consumer: :mezzanine,
      request_module: Chassis.Boundary.ValidateTopology.Request,
      response_module: Chassis.Boundary.ValidateTopology.Response,
      error_module: Chassis.Boundary.ValidateTopology.Error,
      adapters: %{
        local: nil,
        beam_distribution: Chassis.Boundary.BeamDistributionAdapter,
        unix_socket: nil,
        workflow_signal: nil,
        external_http: nil
      },
      mutation?: false,
      idempotency_required?: false,
      authority_required?: true,
      trace_required?: true,
      codec: :canonical_map_v1
    },
    "boundary:mezzanine.chassis.drain_host:v1" => %{
      protocol_ref: "boundary:mezzanine.chassis.drain_host:v1",
      owner: :chassis,
      consumer: :mezzanine,
      request_module: Chassis.Boundary.DrainHost.Request,
      response_module: Chassis.Boundary.DrainHost.Response,
      error_module: Chassis.Boundary.DrainHost.Error,
      adapters: %{
        local: nil,
        beam_distribution: Chassis.Boundary.BeamDistributionAdapter,
        unix_socket: nil,
        workflow_signal: nil,
        external_http: nil
      },
      mutation?: true,
      idempotency_required?: true,
      authority_required?: true,
      trace_required?: true,
      codec: :canonical_map_v1
    },
    "boundary:mezzanine.chassis.provision_host:v1" => %{
      protocol_ref: "boundary:mezzanine.chassis.provision_host:v1",
      owner: :chassis,
      consumer: :mezzanine,
      request_module: Chassis.Boundary.ProvisionHost.Request,
      response_module: Chassis.Boundary.ProvisionHost.Response,
      error_module: Chassis.Boundary.ProvisionHost.Error,
      adapters: %{
        local: nil,
        beam_distribution: Chassis.Boundary.BeamDistributionAdapter,
        unix_socket: nil,
        workflow_signal: nil,
        external_http: nil
      },
      mutation?: true,
      idempotency_required?: true,
      authority_required?: true,
      trace_required?: true,
      codec: :canonical_map_v1
    },
    "boundary:appkit.chassis.read_deployment_projection:v1" => %{
      protocol_ref: "boundary:appkit.chassis.read_deployment_projection:v1",
      owner: :chassis,
      consumer: :app_kit,
      request_module: Chassis.Boundary.ReadDeploymentProjection.Request,
      response_module: Chassis.Boundary.ReadDeploymentProjection.Response,
      error_module: Chassis.Boundary.ReadDeploymentProjection.Error,
      adapters: %{
        local: nil,
        beam_distribution: Chassis.Boundary.BeamDistributionAdapter,
        unix_socket: nil,
        workflow_signal: nil,
        external_http: nil
      },
      mutation?: false,
      idempotency_required?: false,
      authority_required?: false,
      trace_required?: true,
      codec: :canonical_map_v1
    },
    "boundary:stacklab.chassis.run_conformance:v1" => %{
      protocol_ref: "boundary:stacklab.chassis.run_conformance:v1",
      owner: :chassis,
      consumer: :stack_lab,
      request_module: Chassis.Boundary.RunConformance.Request,
      response_module: Chassis.Boundary.RunConformance.Response,
      error_module: Chassis.Boundary.RunConformance.Error,
      adapters: %{
        local: nil,
        beam_distribution: Chassis.Boundary.BeamDistributionAdapter,
        unix_socket: nil,
        workflow_signal: nil,
        external_http: nil
      },
      mutation?: false,
      idempotency_required?: false,
      authority_required?: false,
      trace_required?: true,
      codec: :canonical_map_v1
    }
  }

  @spec adapter_keys() :: [atom()]
  def adapter_keys, do: @adapter_keys

  @spec list() :: [spec()]
  def list do
    @specs
    |> Map.values()
    |> Enum.sort_by(& &1.protocol_ref)
  end

  @spec spec(String.t()) :: {:ok, spec()} | :error
  def spec(protocol_ref), do: Map.fetch(@specs, protocol_ref)

  @spec fetch(String.t()) :: {:ok, spec()} | {:error, :unknown_protocol}
  def fetch(protocol_ref) do
    case spec(protocol_ref) do
      {:ok, spec} -> {:ok, spec}
      :error -> {:error, :unknown_protocol}
    end
  end
end

defmodule Chassis.Boundary.MaterializeDeployment.Request do
  @moduledoc "Request to materialize an application deployment."
  defstruct [
    :topology_ref,
    :service_spec_ref,
    :runtime_profile_ref,
    :placement_ref,
    :environment,
    :git_sha,
    :release_version
  ]
end

defmodule Chassis.Boundary.MaterializeDeployment.Response do
  @moduledoc "Response emitted after deployment materialization."
  defstruct [:deployment_receipt_ref, :app_ref, :node_mesh, :status, :duration_ms]
end

defmodule Chassis.Boundary.MaterializeDeployment.Error do
  @moduledoc "Materialize deployment protocol error payload."
  defstruct [:code, :safe_message, :details]
end

defmodule Chassis.Boundary.RollbackDeployment.Request do
  @moduledoc "Request to roll a deployment back to a prior receipt."
  defstruct [:deployment_receipt_ref, :rollback_ref, :reason, :target_revision]
end

defmodule Chassis.Boundary.RollbackDeployment.Response do
  @moduledoc "Response emitted after deployment rollback."
  defstruct [:rollback_receipt_ref, :status, :restored_revision, :duration_ms]
end

defmodule Chassis.Boundary.RollbackDeployment.Error do
  @moduledoc "Rollback deployment protocol error payload."
  defstruct [:code, :safe_message, :details]
end

defmodule Chassis.Boundary.InspectHost.Request do
  @moduledoc "Request to inspect a Chassis host."
  defstruct [:host_ref, :include_processes?, :include_network?]
end

defmodule Chassis.Boundary.InspectHost.Response do
  @moduledoc "Host inspection response."
  defstruct [:host_ref, :status, :facts, :observed_at]
end

defmodule Chassis.Boundary.InspectHost.Error do
  @moduledoc "Inspect host protocol error payload."
  defstruct [:code, :safe_message, :details]
end

defmodule Chassis.Boundary.ValidateTopology.Request do
  @moduledoc "Request to validate a topology candidate."
  defstruct [:topology_ref, :topology, :profile]
end

defmodule Chassis.Boundary.ValidateTopology.Response do
  @moduledoc "Topology validation response."
  defstruct [:valid?, :violations, :warnings]
end

defmodule Chassis.Boundary.ValidateTopology.Error do
  @moduledoc "Validate topology protocol error payload."
  defstruct [:code, :safe_message, :details]
end

defmodule Chassis.Boundary.DrainHost.Request do
  @moduledoc "Request to drain a host before migration or shutdown."
  defstruct [:host_ref, :deadline_ms, :reason]
end

defmodule Chassis.Boundary.DrainHost.Response do
  @moduledoc "Drain host response."
  defstruct [:host_ref, :status, :duration_ms]
end

defmodule Chassis.Boundary.DrainHost.Error do
  @moduledoc "Drain host protocol error payload."
  defstruct [:code, :safe_message, :details]
end

defmodule Chassis.Boundary.ProvisionHost.Request do
  @moduledoc "Request to provision a Chassis host."
  defstruct [:host_ref, :profile_ref, :ssh_ref, :environment_ref]
end

defmodule Chassis.Boundary.ProvisionHost.Response do
  @moduledoc "Provision host response."
  defstruct [:host_ref, :provisioning_receipt_ref, :status, :duration_ms]
end

defmodule Chassis.Boundary.ProvisionHost.Error do
  @moduledoc "Provision host protocol error payload."
  defstruct [:code, :safe_message, :details]
end

defmodule Chassis.Boundary.ReadDeploymentProjection.Request do
  @moduledoc "Request to read a deployment projection."
  defstruct [:tenant_ref, :installation_ref, :deployment_ref]
end

defmodule Chassis.Boundary.ReadDeploymentProjection.Response do
  @moduledoc "Deployment projection response."
  defstruct [:deployment_ref, :projection, :status]
end

defmodule Chassis.Boundary.ReadDeploymentProjection.Error do
  @moduledoc "Read deployment projection protocol error payload."
  defstruct [:code, :safe_message, :details]
end

defmodule Chassis.Boundary.RunConformance.Request do
  @moduledoc "Request to run boundary conformance proofs."
  defstruct [:proof_refs, :target_ref, :profile]
end

defmodule Chassis.Boundary.RunConformance.Response do
  @moduledoc "Boundary conformance response."
  defstruct [:run_ref, :passed, :failed, :proof_results, :status]
end

defmodule Chassis.Boundary.RunConformance.Error do
  @moduledoc "Run conformance protocol error payload."
  defstruct [:code, :safe_message, :details]
end

defmodule Chassis.Boundary.Scan do
  @moduledoc "Boundary registry scanner."

  alias Chassis.Boundary.Registry

  @spec run([String.t()]) :: {:ok, map()}
  def run(_args \\ []) do
    specs = Registry.list()

    {:ok,
     %{
       protocol_count: length(specs),
       protocol_refs: specs |> Enum.map(& &1.protocol_ref) |> Enum.sort(),
       missing_modules: missing_modules(specs),
       incomplete_adapter_specs: incomplete_adapter_specs(specs)
     }}
  end

  @spec format(map()) :: String.t()
  def format(report) do
    [
      "boundary scan",
      "protocol_count=#{report.protocol_count}",
      "protocol_refs=#{Enum.join(report.protocol_refs, ",")}",
      "missing_modules=#{inspect(report.missing_modules)}",
      "incomplete_adapter_specs=#{inspect(report.incomplete_adapter_specs)}"
    ]
    |> Enum.join("\n")
  end

  defp missing_modules(specs) do
    Enum.flat_map(specs, fn spec ->
      [
        {:request_module, spec.request_module},
        {:response_module, spec.response_module},
        {:error_module, spec.error_module}
      ]
      |> Enum.reject(fn {_kind, module} -> Code.ensure_loaded?(module) end)
      |> Enum.map(fn {kind, module} ->
        %{protocol_ref: spec.protocol_ref, module_kind: kind, module: inspect(module)}
      end)
    end)
  end

  defp incomplete_adapter_specs(specs) do
    expected_keys = Registry.adapter_keys() |> Enum.sort()

    specs
    |> Enum.reject(fn spec -> spec.adapters |> Map.keys() |> Enum.sort() == expected_keys end)
    |> Enum.map(& &1.protocol_ref)
  end
end

defmodule Chassis.Boundary.Conformance do
  @moduledoc "Phase 12 boundary conformance runner."

  alias Chassis.Boundary.{Envelope, Registry, Scan}

  @checks [
    "registry.base_protocol_count",
    "registry.modules_load",
    "registry.adapters_explicit",
    "codec.rejects_pid_payloads",
    "codec.digest_stability",
    "mutations.require_idempotency"
  ]

  @spec run([String.t()]) :: {:ok, map()}
  def run(_args \\ []) do
    failures =
      [
        base_protocol_count(),
        modules_load(),
        adapters_explicit(),
        rejects_pid_payloads(),
        digest_stability(),
        mutations_require_idempotency()
      ]
      |> Enum.reject(&match?({:ok, _name}, &1))
      |> Enum.map(fn {:error, name, reason} -> %{check: name, reason: inspect(reason)} end)

    passed =
      @checks
      |> Enum.reject(fn check -> Enum.any?(failures, &(&1.check == check)) end)

    {:ok, %{passed: passed, failed: failures}}
  end

  @spec format(map()) :: String.t()
  def format(report) do
    [
      "boundary conformance",
      "passed=#{Enum.join(report.passed, ",")}",
      "failed=#{inspect(report.failed)}"
    ]
    |> Enum.join("\n")
  end

  defp base_protocol_count do
    if length(Registry.list()) == 8 do
      {:ok, "registry.base_protocol_count"}
    else
      {:error, "registry.base_protocol_count", {:count, length(Registry.list())}}
    end
  end

  defp modules_load do
    {:ok, scan} = Scan.run([])

    if scan.missing_modules == [] do
      {:ok, "registry.modules_load"}
    else
      {:error, "registry.modules_load", scan.missing_modules}
    end
  end

  defp adapters_explicit do
    {:ok, scan} = Scan.run([])

    if scan.incomplete_adapter_specs == [] do
      {:ok, "registry.adapters_explicit"}
    else
      {:error, "registry.adapters_explicit", scan.incomplete_adapter_specs}
    end
  end

  defp rejects_pid_payloads do
    envelope = Envelope.new!(Map.put(base_attrs(), :payload, %{pid: self()}))

    case encode_rejected?(envelope, "boundary_pid_not_serializable") do
      true -> {:ok, "codec.rejects_pid_payloads"}
      false -> {:error, "codec.rejects_pid_payloads", :accepted_pid_payload}
    end
  end

  defp digest_stability do
    envelope = Envelope.new!(base_attrs())

    if Envelope.digest(envelope) ==
         Envelope.digest(Envelope.new!(Envelope.decode!(Envelope.encode!(envelope)))) do
      {:ok, "codec.digest_stability"}
    else
      {:error, "codec.digest_stability", :digest_changed}
    end
  end

  defp mutations_require_idempotency do
    attrs = Map.delete(base_attrs(), :idempotency_key)

    try do
      _envelope = Envelope.new!(attrs)
      {:error, "mutations.require_idempotency", :accepted_missing_idempotency}
    rescue
      exception in ArgumentError ->
        if String.contains?(Exception.message(exception), "idempotency_key") do
          {:ok, "mutations.require_idempotency"}
        else
          {:error, "mutations.require_idempotency", Exception.message(exception)}
        end
    end
  end

  defp encode_rejected?(envelope, reason) do
    _encoded = Envelope.encode!(envelope)
    false
  rescue
    exception in ArgumentError -> String.contains?(Exception.message(exception), reason)
  end

  defp base_attrs do
    %{
      protocol_ref: "boundary:mezzanine.chassis.materialize_deployment:v1",
      envelope_ref: "env:conformance:1",
      tenant_ref: "tenant:conformance",
      authority_ref: "authority:citadel:snapshot:1",
      idempotency_key: "conformance:1",
      trace_id: "trace:conformance:1",
      status: :request,
      issued_at: ~U[2026-06-02 10:00:00Z],
      payload: %Chassis.Boundary.MaterializeDeployment.Request{
        topology_ref: "topology:conformance",
        service_spec_ref: "service:web",
        environment: :dev,
        git_sha: "abcdef123456",
        release_version: "2026.06.02"
      }
    }
  end
end
