defmodule Chassis.Projection.DeploymentStatus do
  @moduledoc "Operator-safe deployment status projection."

  @derive {Inspect, except: [:safe_labels]}
  defstruct [
    :deployment_ref,
    :receipt_ref,
    :tenant_ref,
    :installation_ref,
    :app_atom,
    :app_ref,
    :topology_ref,
    :status,
    :active_profile,
    :environment,
    :git_sha,
    :release_version,
    :authority_ref,
    :trace_id,
    :updated_at,
    node_mesh: [],
    safe_labels: %{}
  ]

  @type t :: %__MODULE__{
          deployment_ref: String.t() | nil,
          receipt_ref: String.t() | nil,
          tenant_ref: String.t() | nil,
          installation_ref: String.t() | nil,
          app_atom: atom() | nil,
          app_ref: String.t() | nil,
          topology_ref: String.t() | nil,
          status: atom() | nil,
          active_profile: String.t() | nil,
          environment: atom() | nil,
          git_sha: String.t() | nil,
          release_version: String.t() | nil,
          node_mesh: [String.t()],
          authority_ref: String.t() | nil,
          trace_id: String.t() | nil,
          updated_at: DateTime.t() | nil,
          safe_labels: map()
        }
end

defmodule Chassis.Projection.AppStatus do
  @moduledoc "Operator-safe app status projection."

  alias Chassis.Projection.DeploymentStatus

  @spec from_registry(map() | struct()) :: DeploymentStatus.t()
  def from_registry(entry) do
    entry = to_map(entry)

    %DeploymentStatus{
      app_ref: get(entry, :app_ref),
      status: get(entry, :status),
      active_profile: get(entry, :active_profile),
      receipt_ref:
        get(entry, :deployment_receipt_ref) || get(entry, :last_deployment_receipt_ref),
      tenant_ref: get(entry, :tenant_ref),
      installation_ref: get(entry, :installation_ref),
      app_atom: get(entry, :app_atom),
      environment: get(entry, :environment),
      git_sha: get(entry, :git_sha),
      release_version: get(entry, :release_version),
      node_mesh: normalize_node_mesh(get(entry, :node_mesh)),
      updated_at: get(entry, :updated_at) || get(entry, :deployed_at)
    }
  end

  defp to_map(value) when is_struct(value), do: Map.from_struct(value)
  defp to_map(value) when is_map(value), do: value

  defp get(map, key), do: Map.get(map, key) || Map.get(map, Atom.to_string(key))

  defp normalize_node_mesh(nil), do: []
  defp normalize_node_mesh(nodes), do: Enum.map(List.wrap(nodes), &to_string/1)
end

defmodule Chassis.Projection.ChassisDeploymentProjection do
  @moduledoc """
  Reducer for Chassis deployment receipt events.

  The reducer accepts deployment receipt structs or maps from the
  Chassis-to-Mezzanine outbox and produces the operator-safe
  `Chassis.Projection.DeploymentStatus` view.
  """

  alias Chassis.Projection.{DeploymentStatus, Store}
  alias Chassis.Receipts
  alias Chassis.Receipts.DeploymentRecord

  @spec from_receipt(DeploymentRecord.t() | map()) :: DeploymentStatus.t()
  def from_receipt(%DeploymentRecord{} = record), do: from_receipt(Map.from_struct(record))

  def from_receipt(record) when is_map(record) do
    labels = record |> get(:labels, %{}) |> normalize_map()
    safe_labels = Receipts.redact(labels)

    %DeploymentStatus{
      deployment_ref: get(labels, :deployment_ref) || get(record, :app_ref),
      receipt_ref: get(record, :receipt_ref),
      tenant_ref: get(record, :tenant_ref),
      installation_ref: get(labels, :installation_ref) || parse_installation_ref(record, labels),
      app_atom: parse_atom(get(labels, :app_atom)),
      app_ref: get(record, :app_ref),
      topology_ref: get(labels, :topology_ref),
      status: get(record, :status),
      active_profile: get(record, :profile_ref),
      environment: get(record, :env),
      git_sha: get(labels, :git_sha),
      release_version: get(labels, :release_version),
      node_mesh: normalize_node_mesh(get(labels, :node_mesh)),
      authority_ref: get(record, :authority_ref),
      trace_id: get(labels, :trace_id) || get(record, :trace_id),
      updated_at: get(record, :written_at) || DateTime.utc_now(),
      safe_labels: safe_labels
    }
  end

  @spec reduce(map(), keyword()) :: {:ok, DeploymentStatus.t()} | {:error, term()}
  def reduce(%{kind: :chassis_deployment, payload: payload}, opts) do
    projection = from_receipt(payload)

    case Keyword.fetch(opts, :store) do
      {:ok, store} -> Store.Memory.put(store, projection)
      :error -> {:ok, projection}
    end
  end

  def reduce(%{kind: kind}, _opts), do: {:error, {:unsupported_projection_event, kind}}
  def reduce(_event, _opts), do: {:error, :invalid_projection_event}

  defp normalize_map(nil), do: %{}
  defp normalize_map(map) when is_map(map), do: map
  defp normalize_map(_other), do: %{}

  defp get(map, key, default \\ nil) do
    Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  end

  defp parse_atom(value) when is_atom(value), do: value

  defp parse_atom(value) when is_binary(value) do
    String.to_existing_atom(value)
  rescue
    ArgumentError -> nil
  end

  defp parse_atom(_value), do: nil

  defp parse_installation_ref(record, labels) do
    app_ref = get(record, :app_ref)
    tenant_ref = get(record, :tenant_ref)
    app_atom = get(labels, :app_atom)

    with app_ref when is_binary(app_ref) <- app_ref,
         tenant_ref when is_binary(tenant_ref) <- tenant_ref,
         app_atom when is_binary(app_atom) <- app_atom,
         prefix = "app:" <> app_atom <> ":",
         suffix = ":" <> tenant_ref,
         true <- String.starts_with?(app_ref, prefix),
         true <- String.ends_with?(app_ref, suffix) do
      app_ref
      |> String.trim_leading(prefix)
      |> String.trim_trailing(suffix)
    else
      _unknown -> nil
    end
  end

  defp normalize_node_mesh(nil), do: []
  defp normalize_node_mesh(nodes), do: Enum.map(List.wrap(nodes), &to_string/1)
end

defmodule Chassis.Projection.Store.Memory do
  @moduledoc "In-memory projection store for Chassis deployment status rows."

  use GenServer

  alias Chassis.Projection.DeploymentStatus

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)

    case name do
      nil -> GenServer.start_link(__MODULE__, opts, [])
      _ -> GenServer.start_link(__MODULE__, opts, name: name)
    end
  end

  @spec put(GenServer.server(), DeploymentStatus.t()) :: {:ok, DeploymentStatus.t()}
  def put(server, %DeploymentStatus{} = projection),
    do: GenServer.call(server, {:put, projection})

  @spec latest(GenServer.server(), keyword()) ::
          {:ok, DeploymentStatus.t()} | {:error, :not_found}
  def latest(server, query), do: GenServer.call(server, {:latest, query})

  @spec list(GenServer.server()) :: [DeploymentStatus.t()]
  def list(server), do: GenServer.call(server, :list)

  @impl true
  def init(_opts), do: {:ok, %{by_receipt: %{}, order: []}}

  @impl true
  def handle_call({:put, %DeploymentStatus{receipt_ref: receipt_ref} = projection}, _from, state)
      when is_binary(receipt_ref) do
    exists? = Map.has_key?(state.by_receipt, receipt_ref)

    next_state = %{
      state
      | by_receipt: Map.put(state.by_receipt, receipt_ref, projection),
        order: if(exists?, do: state.order, else: [receipt_ref | state.order])
    }

    {:reply, {:ok, projection}, next_state}
  end

  def handle_call({:put, %DeploymentStatus{}}, _from, state),
    do: {:reply, {:error, :receipt_ref_required}, state}

  def handle_call({:latest, query}, _from, state) do
    result =
      state.order
      |> Enum.map(&Map.fetch!(state.by_receipt, &1))
      |> Enum.filter(&matches_query?(&1, query))
      |> List.first()

    case result do
      nil -> {:reply, {:error, :not_found}, state}
      projection -> {:reply, {:ok, projection}, state}
    end
  end

  def handle_call(:list, _from, state) do
    projections =
      state.order
      |> Enum.reverse()
      |> Enum.map(&Map.fetch!(state.by_receipt, &1))

    {:reply, projections, state}
  end

  defp matches_query?(%DeploymentStatus{} = projection, query) do
    Enum.all?(query, fn {key, expected} -> Map.get(projection, key) == expected end)
  end
end
