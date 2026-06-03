defmodule Chassis.Releases.Bundle do
  @moduledoc """
  Release tarball materializer with SHA-256 validation.
  """

  @enforce_keys [:path, :bytes, :sha256, :size_bytes, :materialized_at]
  defstruct [:path, :bytes, :sha256, :size_bytes, :materialized_at]

  @type t :: %__MODULE__{
          path: Path.t(),
          bytes: binary(),
          sha256: String.t(),
          size_bytes: non_neg_integer(),
          materialized_at: DateTime.t()
        }

  @spec materialize(Path.t(), keyword()) :: {:ok, t()} | {:error, term()}
  def materialize(path, opts \\ []) when is_binary(path) do
    with {:ok, bytes} <- File.read(path),
         actual = sha256(bytes),
         :ok <- validate_digest(actual, Keyword.get(opts, :expected_sha256)) do
      {:ok,
       %__MODULE__{
         path: path,
         bytes: bytes,
         sha256: actual,
         size_bytes: byte_size(bytes),
         materialized_at: DateTime.utc_now()
       }}
    end
  end

  @spec sha256(binary()) :: String.t()
  def sha256(bytes),
    do: "sha256:" <> (:crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower))

  @spec validate(binary(), String.t()) :: :ok | {:error, :sha256_mismatch}
  def validate(bytes, digest),
    do: if(sha256(bytes) == digest, do: :ok, else: {:error, :sha256_mismatch})

  defp validate_digest(_actual, nil), do: :ok
  defp validate_digest(actual, actual), do: :ok
  defp validate_digest(actual, expected), do: {:error, {:sha256_mismatch, expected, actual}}
end

defmodule Chassis.AppRegistry.Entry do
  @moduledoc """
  Registry entry for a deployed end-user application.
  """

  @fields [
    :app_ref,
    :app_atom,
    :installation_ref,
    :tenant_ref,
    :active_profile,
    :environment,
    :git_sha,
    :release_version,
    :node_mesh,
    :status,
    :last_deployment_receipt_ref,
    :rollback_target_ref,
    :deployed_at,
    :updated_at
  ]

  @required [
    :app_ref,
    :app_atom,
    :installation_ref,
    :tenant_ref,
    :active_profile,
    :environment,
    :git_sha,
    :release_version,
    :last_deployment_receipt_ref
  ]

  @environments [:dev, :prod]
  @statuses [:deploying, :active, :degraded, :failed, :rolling_back]

  @enforce_keys @required
  defstruct @fields

  @type status :: :deploying | :active | :degraded | :failed | :rolling_back
  @type environment :: :dev | :prod
  @type app_atom :: :extravaganza | :stack_coder | atom()

  @type t :: %__MODULE__{
          app_ref: String.t(),
          app_atom: app_atom(),
          installation_ref: String.t(),
          tenant_ref: String.t(),
          active_profile: String.t(),
          environment: environment(),
          git_sha: String.t(),
          release_version: String.t(),
          node_mesh: [atom()],
          status: status(),
          last_deployment_receipt_ref: String.t(),
          rollback_target_ref: String.t() | nil,
          deployed_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  @spec fields() :: [atom()]
  def fields, do: @fields

  @spec new(map() | keyword()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_list(attrs) or is_map(attrs) do
    attrs =
      attrs
      |> Map.new()
      |> Map.update(:environment, nil, &normalize_env/1)
      |> Map.update(:status, :active, &normalize_status/1)
      |> Map.put_new(:node_mesh, [])

    with :ok <- require_fields(attrs),
         :ok <- validate_environment(attrs.environment),
         :ok <- validate_status(attrs.status),
         :ok <- validate_binary_fields(attrs),
         :ok <- validate_node_mesh(attrs.node_mesh) do
      now = DateTime.utc_now()

      {:ok,
       struct!(
         __MODULE__,
         attrs
         |> Map.take(@fields)
         |> Map.put_new(:deployed_at, now)
         |> Map.put_new(:updated_at, now)
       )}
    end
  end

  @spec new!(map() | keyword()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, entry} -> entry
      {:error, reason} -> raise ArgumentError, "invalid app registry entry: #{inspect(reason)}"
    end
  end

  @spec statuses() :: [status()]
  def statuses, do: @statuses

  defp require_fields(attrs) do
    case Enum.find(@required, &blank?(Map.get(attrs, &1))) do
      nil -> :ok
      field -> {:error, {:missing_required, field}}
    end
  end

  defp validate_environment(env) when env in @environments, do: :ok
  defp validate_environment(env), do: {:error, {:invalid_environment, env}}

  defp validate_status(status) when status in @statuses, do: :ok
  defp validate_status(status), do: {:error, {:invalid_status, status}}

  defp validate_binary_fields(attrs) do
    fields = [
      :app_ref,
      :installation_ref,
      :tenant_ref,
      :active_profile,
      :git_sha,
      :release_version,
      :last_deployment_receipt_ref
    ]

    case Enum.find(fields, &(not is_binary(Map.get(attrs, &1)))) do
      nil -> :ok
      field -> {:error, {:invalid_field, field, Map.get(attrs, field)}}
    end
  end

  defp validate_node_mesh(nodes) when is_list(nodes) do
    if Enum.all?(nodes, &is_atom/1), do: :ok, else: {:error, {:invalid_node_mesh, nodes}}
  end

  defp validate_node_mesh(nodes), do: {:error, {:invalid_node_mesh, nodes}}

  defp normalize_env(env) when is_binary(env), do: String.to_existing_atom(env)
  defp normalize_env(env), do: env

  defp normalize_status(status) when is_binary(status), do: String.to_existing_atom(status)
  defp normalize_status(status), do: status

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(_), do: false
end

defmodule Chassis.AppRegistry.Backend do
  @moduledoc "Storage adapter behaviour for the Chassis App Registry."

  alias Chassis.AppRegistry.Entry

  @type state :: term()
  @type query :: keyword()

  @callback init(keyword()) :: {:ok, state()} | {:error, term()}
  @callback put(state(), Entry.t()) :: :ok | {:error, term()}
  @callback get(state(), String.t()) :: {:ok, Entry.t()} | :error | {:error, term()}
  @callback list(state(), query()) :: {:ok, [Entry.t()]} | {:error, term()}
  @callback delete(state(), String.t()) :: :ok | {:error, term()}
end

defmodule Chassis.AppRegistry.Backend.Ets do
  @moduledoc """
  ETS-backed app registry backend.

  The table is private to the owning `Chassis.AppRegistry` process, so callers
  must go through the GenServer. ETS provides atomic insert/lookup and safe
  concurrent readers under the server's serialization.
  """

  @behaviour Chassis.AppRegistry.Backend

  alias Chassis.AppRegistry.Entry

  @impl true
  def init(_opts) do
    {:ok, :ets.new(:chassis_app_registry, [:set, :private, read_concurrency: true])}
  end

  @impl true
  def put(table, %Entry{} = entry) do
    :ets.insert(table, {entry.app_ref, entry})
    :ok
  end

  @impl true
  def get(table, app_ref) do
    case :ets.lookup(table, app_ref) do
      [{^app_ref, entry}] -> {:ok, entry}
      [] -> :error
    end
  end

  @impl true
  def list(table, query) do
    entries =
      table
      |> :ets.tab2list()
      |> Enum.map(fn {_ref, entry} -> entry end)
      |> Enum.filter(&matches_query?(&1, query))
      |> Enum.sort_by(& &1.app_ref)

    {:ok, entries}
  end

  @impl true
  def delete(table, app_ref) do
    :ets.delete(table, app_ref)
    :ok
  end

  defp matches_query?(%Entry{} = entry, query) do
    Enum.all?(query, fn
      {:app_atom, value} -> entry.app_atom == value
      {:tenant_ref, value} -> entry.tenant_ref == value
      {:status, value} -> entry.status == value
      {:environment, value} -> entry.environment == value
      _ -> true
    end)
  end
end

defmodule Chassis.AppRegistry.Backend.AshPostgres do
  @moduledoc """
  Future Postgres-backed AppRegistry adapter.

  Phase 11 activates the ETS backend only. The Postgres backend must never
  report success until the database resource is actually wired.
  """

  @behaviour Chassis.AppRegistry.Backend

  @impl true
  def init(_opts), do: {:error, {:not_implemented, __MODULE__}}
  @impl true
  def put(_state, _entry), do: {:error, {:not_implemented, __MODULE__}}
  @impl true
  def get(_state, _app_ref), do: {:error, {:not_implemented, __MODULE__}}
  @impl true
  def list(_state, _query), do: {:error, {:not_implemented, __MODULE__}}
  @impl true
  def delete(_state, _app_ref), do: {:error, {:not_implemented, __MODULE__}}
end

defmodule Chassis.AppRegistry do
  @moduledoc """
  GenServer-backed single source of truth for active deployed applications.
  """

  use GenServer

  alias Chassis.AppRegistry.Backend
  alias Chassis.AppRegistry.Entry

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)

    case name do
      nil -> GenServer.start_link(__MODULE__, opts, [])
      _ -> GenServer.start_link(__MODULE__, opts, name: name)
    end
  end

  @spec register(Entry.t()) :: {:ok, Entry.t()} | {:error, term()}
  def register(%Entry{} = entry), do: register(__MODULE__, entry)

  @spec register(GenServer.server(), Entry.t()) :: {:ok, Entry.t()} | {:error, term()}
  def register(server, %Entry{} = entry), do: GenServer.call(server, {:register, entry})

  @spec update_status(String.t(), Entry.status(), keyword()) :: :ok | {:error, term()}
  def update_status(app_ref, status, extras \\ []),
    do: update_status(__MODULE__, app_ref, status, extras)

  @spec update_status(GenServer.server(), String.t(), Entry.status(), keyword()) ::
          :ok | {:error, term()}
  def update_status(server, app_ref, status, extras),
    do: GenServer.call(server, {:update_status, app_ref, status, extras})

  @spec lookup(String.t()) :: {:ok, Entry.t()} | {:error, :not_found}
  def lookup(app_ref), do: lookup(__MODULE__, app_ref)

  @spec lookup(GenServer.server(), String.t()) :: {:ok, Entry.t()} | {:error, :not_found}
  def lookup(server, app_ref), do: GenServer.call(server, {:lookup, app_ref})

  @spec list(keyword()) :: {:ok, [Entry.t()]} | {:error, term()}
  def list(query \\ []), do: list(__MODULE__, query)

  @spec list(GenServer.server(), keyword()) :: {:ok, [Entry.t()]} | {:error, term()}
  def list(server, query), do: GenServer.call(server, {:list, query})

  @spec active_profile(String.t()) :: {:ok, String.t()} | {:error, :not_found}
  def active_profile(app_ref), do: active_profile(__MODULE__, app_ref)

  @spec active_profile(GenServer.server(), String.t()) :: {:ok, String.t()} | {:error, :not_found}
  def active_profile(server, app_ref) do
    case lookup(server, app_ref) do
      {:ok, %Entry{active_profile: profile}} -> {:ok, profile}
      error -> error
    end
  end

  @impl true
  def init(opts) do
    backend = Keyword.get(opts, :backend, Backend.Ets)
    backend_opts = Keyword.get(opts, :backend_opts, [])

    with {:ok, backend_state} <- backend.init(backend_opts) do
      {:ok, %{backend: backend, backend_state: backend_state}}
    end
  end

  @impl true
  def handle_call({:register, %Entry{} = incoming}, _from, state) do
    entry = resolve_conflict(state, incoming)

    case state.backend.put(state.backend_state, entry) do
      :ok -> {:reply, {:ok, entry}, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:update_status, app_ref, status, extras}, _from, state) do
    with :ok <- validate_status(status),
         {:ok, entry} <- backend_lookup(state, app_ref) do
      updated =
        extras
        |> Map.new()
        |> Enum.reduce(%{entry | status: status, updated_at: DateTime.utc_now()}, fn
          {:rollback_target_ref, value}, acc ->
            %{acc | rollback_target_ref: value}

          {:last_deployment_receipt_ref, value}, acc ->
            %{acc | last_deployment_receipt_ref: value}

          {:active_profile, value}, acc ->
            %{acc | active_profile: value}

          {:node_mesh, value}, acc ->
            %{acc | node_mesh: value}

          _other, acc ->
            acc
        end)

      case state.backend.put(state.backend_state, updated) do
        :ok -> {:reply, :ok, state}
        {:error, reason} -> {:reply, {:error, reason}, state}
      end
    else
      :error -> {:reply, {:error, :not_found}, state}
      error -> {:reply, error, state}
    end
  end

  def handle_call({:lookup, app_ref}, _from, state) do
    case backend_lookup(state, app_ref) do
      {:ok, entry} -> {:reply, {:ok, entry}, state}
      :error -> {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:list, query}, _from, state) do
    {:reply, state.backend.list(state.backend_state, query), state}
  end

  defp resolve_conflict(state, %Entry{} = incoming) do
    case backend_lookup(state, incoming.app_ref) do
      {:ok, current} ->
        %{
          incoming
          | rollback_target_ref:
              incoming.rollback_target_ref || current.last_deployment_receipt_ref,
            deployed_at: current.deployed_at,
            updated_at: DateTime.utc_now()
        }

      :error ->
        incoming
    end
  end

  defp backend_lookup(state, app_ref), do: state.backend.get(state.backend_state, app_ref)

  defp validate_status(status) do
    if status in Entry.statuses(), do: :ok, else: {:error, {:invalid_status, status}}
  end
end

defmodule Chassis.Releases.ApprovedMounts do
  @moduledoc "Approved state volume mounts."

  @spec list(String.t(), String.t()) :: [map()]
  def list(_app_ref, _profile_ref),
    do: [%{path: "/var/lib/nshkr/state", kind: :mutable_state, mode: :rw}]
end
