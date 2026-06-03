defmodule Chassis.Host.Daemon do
  @moduledoc "Host-resident daemon facade and status surface."

  alias Chassis.Host.Daemon.Router

  @default_socket_path "/var/run/nshkr_chassis_host.sock"
  @socket_mode "0660"
  @socket_owner "nshkr_chassis_host:nshkr_chassis_host"

  @spec status(keyword()) :: map()
  def status(opts \\ []) do
    %{
      state: :running,
      socket_path: Keyword.get(opts, :socket_path, @default_socket_path),
      socket_mode: @socket_mode,
      socket_owner: @socket_owner,
      peer_acl: Keyword.get(opts, :allowed_uids, [0]),
      protocol: :unix_socket
    }
  end

  @spec route(Chassis.Boundary.Envelope.t(), keyword()) ::
          {:ok, map()} | {:error, Chassis.Boundary.Error.t()}
  def route(envelope, opts \\ []), do: Router.route(envelope, opts)
end

defmodule Chassis.Host.Daemon.Socket do
  @moduledoc """
  AF_UNIX framing helpers.

  Frames are a 4-byte big-endian byte length followed by a compressed Erlang
  external-term payload. Decoding uses `:safe` to reject unsafe terms.
  """

  @spec encode_frame(term()) :: binary()
  def encode_frame(term) do
    payload = :erlang.term_to_binary(term, [:compressed])
    <<byte_size(payload)::32-big, payload::binary>>
  end

  @spec decode_frame(binary()) ::
          {:ok, term(), binary()} | {:error, :incomplete_frame | :invalid_frame}
  def decode_frame(<<size::32-big, rest::binary>>) when byte_size(rest) >= size do
    <<payload::binary-size(size), remainder::binary>> = rest
    {:ok, :erlang.binary_to_term(payload, [:safe]), remainder}
  rescue
    _error -> {:error, :invalid_frame}
  end

  def decode_frame(_binary), do: {:error, :incomplete_frame}
end

defmodule Chassis.Host.Daemon.Identity do
  @moduledoc "Peer identity and UID ACL checks for the Unix socket."

  alias Chassis.Boundary.Error

  @spec authorize_peer(map(), keyword()) :: :ok | {:error, Error.t()}
  def authorize_peer(peer, opts \\ []) when is_map(peer) do
    uid = Map.get(peer, :uid) || Map.get(peer, "uid")

    allowed_uids =
      Keyword.get(
        opts,
        :allowed_uids,
        Application.get_env(:chassis_host_daemon, :allowed_uids, [0])
      )

    if uid in allowed_uids do
      :ok
    else
      {:error,
       Error.new(:authority_denied,
         safe_message: "peer uid #{inspect(uid)} is not allowed for host daemon socket",
         retry_posture: :operator_required
       )}
    end
  end
end

defmodule Chassis.Host.Daemon.AuthCache do
  @moduledoc "Local Citadel authority snapshot cache with TTL-aware entries."

  @type outcome :: :allowed | :denied
  @type entry :: %{authority_ref: String.t(), outcome: outcome(), inserted_at: DateTime.t()}

  @spec start_link(keyword()) :: Agent.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)

    case name do
      nil -> Agent.start_link(fn -> %{} end, opts)
      name -> Agent.start_link(fn -> %{} end, Keyword.put(opts, :name, name))
    end
  end

  @spec put(pid() | atom(), String.t(), outcome(), keyword()) :: :ok
  def put(cache \\ __MODULE__, authority_ref, outcome, opts \\ [])
      when is_binary(authority_ref) and outcome in [:allowed, :denied] do
    entry = %{
      authority_ref: authority_ref,
      outcome: outcome,
      inserted_at: Keyword.get(opts, :inserted_at, DateTime.utc_now())
    }

    Agent.update(cache, &Map.put(&1, authority_ref, entry))
  end

  @spec get(pid() | atom(), String.t()) :: {:ok, entry()} | :error
  def get(cache \\ __MODULE__, authority_ref) when is_binary(authority_ref) do
    case Agent.get(cache, &Map.get(&1, authority_ref)) do
      nil -> :error
      entry -> {:ok, entry}
    end
  end
end

defmodule Chassis.Host.Daemon.IdempotencyTable do
  @moduledoc "In-memory host-daemon idempotency table."

  @spec start_link(keyword()) :: Agent.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)

    case name do
      nil -> Agent.start_link(fn -> %{} end, opts)
      name -> Agent.start_link(fn -> %{} end, Keyword.put(opts, :name, name))
    end
  end

  @spec execute(pid() | atom(), String.t(), (-> term())) :: term()
  def execute(table \\ __MODULE__, idempotency_key, fun)
      when is_binary(idempotency_key) and is_function(fun, 0) do
    Agent.get_and_update(table, fn state ->
      case Map.fetch(state, idempotency_key) do
        {:ok, cached} ->
          {cached, state}

        :error ->
          result = fun.()
          {result, Map.put(state, idempotency_key, result)}
      end
    end)
  end
end

defmodule Chassis.Host.Daemon.Auth do
  @moduledoc "Per-envelope authority re-verification for host-daemon mutations."

  alias Chassis.Boundary.{Envelope, Error}
  alias Chassis.Host.Daemon.AuthCache

  @default_ttl_ms 300_000

  @spec reverify(Envelope.t(), keyword()) :: :ok | {:error, Error.t()}
  def reverify(%Envelope{} = envelope, opts \\ []) do
    with :ok <- ensure_mutation_authorized(envelope),
         {:ok, entry} <- fetch_snapshot(envelope, opts),
         :ok <- ensure_snapshot_allowed(envelope, entry),
         :ok <- ensure_snapshot_fresh(envelope, entry, opts) do
      :ok
    end
  end

  defp ensure_mutation_authorized(%Envelope{} = envelope) do
    payload = payload_map(envelope.payload)

    Chassis.Policy.Boundary.assert_mutation_authorized(%{
      intent_ref: Map.get(payload, :intent_ref) || Map.get(payload, "intent_ref"),
      authority_ref: envelope.authority_ref,
      operator_consent_ref:
        Map.get(payload, :operator_consent_ref) || Map.get(payload, "operator_consent_ref")
    })
  end

  defp fetch_snapshot(%Envelope{} = envelope, opts) do
    cache = Keyword.get(opts, :auth_cache, AuthCache)

    case AuthCache.get(cache, envelope.authority_ref) do
      {:ok, entry} ->
        {:ok, entry}

      :error ->
        {:error,
         Error.new(:authority_denied, envelope,
           safe_message: "authority snapshot missing for #{envelope.authority_ref}",
           retry_posture: :operator_required
         )}
    end
  end

  defp ensure_snapshot_allowed(%Envelope{}, %{outcome: :allowed}), do: :ok

  defp ensure_snapshot_allowed(%Envelope{} = envelope, _entry) do
    {:error,
     Error.new(:authority_denied, envelope,
       safe_message: "authority snapshot denied #{envelope.authority_ref}",
       retry_posture: :operator_required
     )}
  end

  defp ensure_snapshot_fresh(
         %Envelope{} = envelope,
         %{inserted_at: %DateTime{} = inserted_at},
         opts
       ) do
    now = Keyword.get(opts, :now, DateTime.utc_now())
    ttl_ms = Keyword.get(opts, :ttl_ms, @default_ttl_ms)

    if DateTime.diff(now, inserted_at, :millisecond) <= ttl_ms do
      :ok
    else
      {:error,
       Error.new(:authority_denied, envelope,
         safe_message: "authority snapshot stale for #{envelope.authority_ref}",
         retry_posture: :operator_required
       )}
    end
  end

  defp ensure_snapshot_fresh(%Envelope{} = envelope, _entry, _opts) do
    {:error,
     Error.new(:authority_denied, envelope,
       safe_message: "authority snapshot missing inserted_at",
       retry_posture: :operator_required
     )}
  end

  defp payload_map(%_struct{} = payload), do: Map.from_struct(payload)
  defp payload_map(payload) when is_map(payload), do: payload
  defp payload_map(_payload), do: %{}
end

defmodule Chassis.Host.Daemon.Router do
  @moduledoc "Host daemon envelope router."

  alias Chassis.Boundary.{Envelope, Error}
  alias Chassis.Host.Daemon.{Auth, IdempotencyTable, Identity}

  @spec route(Envelope.t(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def route(%Envelope{} = envelope, opts \\ []) do
    with :ok <- Identity.authorize_peer(Keyword.get(opts, :peer, %{uid: 0}), opts),
         :ok <- Auth.reverify(envelope, opts),
         {:ok, idempotency_key} <- idempotency_key(envelope) do
      table = Keyword.get(opts, :idempotency_table, IdempotencyTable)
      IdempotencyTable.execute(table, idempotency_key, fn -> dispatch(envelope, opts) end)
    end
  end

  defp dispatch(%Envelope{} = envelope, opts) do
    handlers = Keyword.get(opts, :handlers, %{})

    case Map.get(handlers, envelope.protocol_ref) do
      handler when is_function(handler, 1) ->
        handler.(envelope)

      nil ->
        {:ok,
         %{
           state: :accepted,
           protocol_ref: envelope.protocol_ref,
           envelope_ref: envelope.envelope_ref
         }}
    end
  end

  defp idempotency_key(%Envelope{idempotency_key: key}) when is_binary(key) and key != "",
    do: {:ok, key}

  defp idempotency_key(%Envelope{} = envelope) do
    {:error,
     Error.new(:idempotency_key_required, envelope,
       safe_message: "host daemon requires idempotency_key",
       retry_posture: :non_retryable
     )}
  end
end
