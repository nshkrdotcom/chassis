defmodule Chassis.Boundary do
  @moduledoc "Ring 0 boundary dispatcher."
  @spec dispatch(String.t(), map()) :: {:ok, map()} | {:error, term()}
  def dispatch(protocol_ref, envelope),
    do: Chassis.Boundary.LocalAdapter.dispatch(protocol_ref, envelope)
end

defmodule Chassis.Boundary.Protocol do
  @moduledoc "Boundary protocol behaviour."
  @callback dispatch(String.t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
end

defmodule Chassis.Boundary.Envelope do
  @moduledoc "Canonical request envelope."
  @enforce_keys [
    :protocol_ref,
    :tenant_ref,
    :authority_ref,
    :idempotency_key,
    :trace_id,
    :payload
  ]
  defstruct [
    :protocol_ref,
    :tenant_ref,
    :authority_ref,
    :idempotency_key,
    :trace_id,
    :payload,
    :actor_ref,
    :issued_at
  ]

  @type t :: %__MODULE__{
          protocol_ref: String.t(),
          tenant_ref: String.t(),
          authority_ref: String.t(),
          idempotency_key: String.t(),
          trace_id: String.t(),
          payload: map(),
          actor_ref: String.t() | nil,
          issued_at: DateTime.t() | nil
        }

  @spec new!(map()) :: t()
  def new!(attrs) when is_map(attrs) do
    required = [:protocol_ref, :tenant_ref, :authority_ref, :idempotency_key, :trace_id, :payload]

    case Enum.filter(required, &blank?(Map.get(attrs, &1))) do
      [] -> struct!(__MODULE__, Map.put_new(attrs, :issued_at, DateTime.utc_now()))
      missing -> raise ArgumentError, "missing boundary fields: #{inspect(missing)}"
    end
  end

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(_value), do: false
end

defmodule Chassis.Boundary.Error do
  @moduledoc "Boundary error taxonomy."
  defstruct [:code, :message, :retryable?]

  @type t :: %__MODULE__{
          code: atom() | nil,
          message: String.t() | nil,
          retryable?: boolean() | nil
        }
  @spec new(atom(), String.t(), boolean()) :: t()
  def new(code, message, retryable? \\ false),
    do: %__MODULE__{code: code, message: message, retryable?: retryable?}
end

defmodule Chassis.Boundary.Registry do
  @moduledoc "Boundary protocol registry."
  @protocols [
    "boundary:mezzanine.chassis.materialize_deployment:v1",
    "boundary:mezzanine.chassis.rollback_deployment:v1",
    "boundary:mezzanine.chassis.inspect_host:v1",
    "boundary:mezzanine.chassis.validate_topology:v1",
    "boundary:mezzanine.chassis.drain_host:v1",
    "boundary:mezzanine.chassis.provision_host:v1",
    "boundary:appkit.chassis.read_status:v1",
    "boundary:stacklab.chassis.run_conformance:v1",
    "boundary:mezzanine.chassis.evolution.create_failure_batch:v1",
    "boundary:mezzanine.chassis.evolution.flag_turn:v1",
    "boundary:mezzanine.chassis.evolution.start:v1",
    "boundary:mezzanine.chassis.evolution.stop:v1",
    "boundary:mezzanine.chassis.evolution.get_status:v1",
    "boundary:mezzanine.chassis.evolution.provision_trial_node:v1",
    "boundary:mezzanine.chassis.evolution.run_trial_replay:v1",
    "boundary:mezzanine.chassis.evolution.score_candidate:v1",
    "boundary:mezzanine.chassis.evolution.request_promotion:v1",
    "boundary:mezzanine.chassis.evolution.promote_candidate:v1",
    "boundary:mezzanine.chassis.evolution.rollback_candidate:v1",
    "boundary:mezzanine.chassis.evolution.inspect_candidate:v1",
    "boundary:chassis.host_daemon.start_trial:v1",
    "boundary:chassis.host_daemon.stop_trial:v1",
    "boundary:chassis.host_daemon.build_candidate:v1",
    "boundary:chassis.host_daemon.swap_candidate:v1",
    "boundary:chassis.host_daemon.health_probe:v1",
    "boundary:chassis.host_daemon.rollback_swap:v1",
    "boundary:chassis.model.materialize_weight:v1",
    "boundary:chassis.model.verify_weight:v1",
    "boundary:chassis.model.reload_tensor_patch:v1",
    "boundary:chassis.model.rollback_tensor_patch:v1",
    "boundary:chassis.hardware.validate_accelerator:v1"
  ]

  @spec all() :: [map()]
  def all,
    do:
      Enum.map(
        @protocols,
        &%{
          protocol_ref: &1,
          adapters: %{
            local: Chassis.Boundary.LocalAdapter,
            beam: Chassis.Boundary.BeamDistributionAdapter,
            unix_socket: Chassis.Boundary.UnixSocketAdapter,
            workflow_signal: nil,
            external_http: nil
          }
        }
      )

  @spec fetch(String.t()) :: {:ok, map()} | {:error, :unknown_protocol}
  def fetch(ref) do
    case Enum.find(all(), &(&1.protocol_ref == ref)) do
      nil -> {:error, :unknown_protocol}
      spec -> {:ok, spec}
    end
  end
end

defmodule Chassis.Boundary.Codec do
  @moduledoc "Local codec posture matching GroundPlane constraints for smoke."
  @sensitive ~w(secret password private_key material token raw_credential)
  @spec encode!(term()) :: binary()
  def encode!(term) do
    case validate(term) do
      :ok -> :erlang.term_to_binary(term)
      {:error, reason} -> raise ArgumentError, inspect(reason)
    end
  end

  @spec decode!(binary()) :: term()
  def decode!(binary), do: :erlang.binary_to_term(binary)

  @spec validate(term()) :: :ok | {:error, term()}
  def validate(pid) when is_pid(pid), do: {:error, :boundary_pid_not_serializable}

  def validate(map) when is_map(map),
    do:
      Enum.reduce_while(map, :ok, fn {key, value}, :ok ->
        if sensitive?(key),
          do: {:halt, {:error, {:raw_credential_key_forbidden, key}}},
          else: reduce_value(value)
      end)

  def validate(list) when is_list(list),
    do: Enum.reduce_while(list, :ok, fn value, :ok -> reduce_value(value) end)

  def validate(_value), do: :ok

  defp reduce_value(value) do
    case validate(value) do
      :ok -> {:cont, :ok}
      error -> {:halt, error}
    end
  end

  defp sensitive?(key),
    do: Enum.any?(@sensitive, &String.contains?(String.downcase(to_string(key)), &1))
end

defmodule Chassis.Boundary.LocalAdapter do
  @moduledoc "Local boundary adapter."
  @spec dispatch(String.t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def dispatch(protocol_ref, envelope, _opts \\ []) do
    with {:ok, _spec} <- Chassis.Boundary.Registry.fetch(protocol_ref),
         :ok <- Chassis.Boundary.Codec.validate(envelope) do
      {:ok, %{protocol_ref: protocol_ref, status: :accepted, envelope_digest: digest(envelope)}}
    end
  end

  defp digest(value),
    do:
      "sha256:" <>
        (:crypto.hash(:sha256, :erlang.term_to_binary(value)) |> Base.encode16(case: :lower))
end

defmodule Chassis.Boundary.BeamDistributionAdapter do
  @moduledoc "BEAM-distribution boundary adapter."
  defdelegate dispatch(protocol_ref, envelope, opts \\ []), to: Chassis.Boundary.LocalAdapter
end

defmodule Chassis.Boundary.UnixSocketAdapter do
  @moduledoc "Unix socket boundary adapter for Host Daemon."
  defdelegate dispatch(protocol_ref, envelope, opts \\ []), to: Chassis.Boundary.LocalAdapter
end

for boundary <- [
      MaterializeDeployment,
      RollbackDeployment,
      InspectHost,
      ValidateTopology,
      DrainHost,
      ProvisionHost,
      ReadStatus,
      RunConformance
    ] do
  defmodule Module.concat([Chassis.Boundary, boundary, Request]) do
    @moduledoc "Boundary request DTO."
    defstruct [:tenant_ref, :installation_ref, :payload]

    @type t :: %__MODULE__{
            tenant_ref: String.t() | nil,
            installation_ref: String.t() | nil,
            payload: map() | nil
          }
  end

  defmodule Module.concat([Chassis.Boundary, boundary, Response]) do
    @moduledoc "Boundary response DTO."
    defstruct [:status, :payload, :receipt_ref]

    @type t :: %__MODULE__{
            status: atom() | nil,
            payload: map() | nil,
            receipt_ref: String.t() | nil
          }
  end
end
