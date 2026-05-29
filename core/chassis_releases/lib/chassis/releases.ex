defmodule Chassis.Releases.Bundle do
  @moduledoc "Release tarball materializer with SHA-256 validation."
  @spec sha256(binary()) :: String.t()
  def sha256(bytes),
    do: "sha256:" <> (:crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower))

  @spec validate(binary(), String.t()) :: :ok | {:error, :sha256_mismatch}
  def validate(bytes, digest),
    do: if(sha256(bytes) == digest, do: :ok, else: {:error, :sha256_mismatch})
end

defmodule Chassis.AppRegistry.Entry do
  @moduledoc "Registry entry for deployed applications."
  @fields [
    :app_ref,
    :active_profile,
    :git_sha,
    :mesh_ref,
    :deployment_receipt_ref,
    :rollback_receipt_ref,
    :tenant_ref,
    :installation_ref,
    :status,
    :nodes,
    :authority_ref,
    :trace_id,
    :updated_at
  ]
  @enforce_keys [:app_ref, :active_profile]
  defstruct @fields
  @type t :: %__MODULE__{}
  @spec fields() :: [atom()]
  def fields, do: @fields
end

defmodule Chassis.AppRegistry.Backend do
  @moduledoc "App registry backend behaviour."
  @callback put(Chassis.AppRegistry.Entry.t()) :: :ok
  @callback get(String.t()) :: {:ok, Chassis.AppRegistry.Entry.t()} | {:error, :not_found}
  @callback list(keyword()) :: [Chassis.AppRegistry.Entry.t()]
end

defmodule Chassis.AppRegistry.Backend.Ets do
  @moduledoc "ETS-backed app registry."
  @table :chassis_app_registry
  @spec put(Chassis.AppRegistry.Entry.t()) :: :ok
  def put(entry) do
    ensure_table()
    :ets.insert(@table, {entry.app_ref, %{entry | updated_at: DateTime.utc_now()}})
    :ok
  end

  @spec get(String.t()) :: {:ok, Chassis.AppRegistry.Entry.t()} | {:error, :not_found}
  def get(app_ref) do
    ensure_table()

    case :ets.lookup(@table, app_ref) do
      [{^app_ref, entry}] -> {:ok, entry}
      [] -> {:error, :not_found}
    end
  end

  @spec list(keyword()) :: [Chassis.AppRegistry.Entry.t()]
  def list(_opts \\ []) do
    ensure_table()
    @table |> :ets.tab2list() |> Enum.map(fn {_key, entry} -> entry end)
  end

  defp ensure_table do
    case :ets.info(@table) do
      :undefined -> :ets.new(@table, [:named_table, :public])
      _info -> @table
    end
  end
end

defmodule Chassis.AppRegistry.Backend.AshPostgres do
  @moduledoc "Future Postgres registry backend facade."
  defdelegate put(entry), to: Chassis.AppRegistry.Backend.Ets
  defdelegate get(app_ref), to: Chassis.AppRegistry.Backend.Ets
  defdelegate list(opts \\ []), to: Chassis.AppRegistry.Backend.Ets
end

defmodule Chassis.AppRegistry do
  @moduledoc "Single source of truth for active_profile."
  @spec register(map()) :: {:ok, Chassis.AppRegistry.Entry.t()}
  def register(attrs) do
    entry = struct!(Chassis.AppRegistry.Entry, Map.put_new(attrs, :status, :active))
    :ok = Chassis.AppRegistry.Backend.Ets.put(entry)
    {:ok, entry}
  end

  defdelegate get(app_ref), to: Chassis.AppRegistry.Backend.Ets
  defdelegate list(opts \\ []), to: Chassis.AppRegistry.Backend.Ets
end

defmodule Chassis.Releases.ApprovedMounts do
  @moduledoc "Approved state volume mounts."
  @spec list(String.t(), String.t()) :: [map()]
  def list(_app_ref, _profile_ref),
    do: [%{path: "/var/lib/nshkr/state", kind: :mutable_state, mode: :rw}]
end
