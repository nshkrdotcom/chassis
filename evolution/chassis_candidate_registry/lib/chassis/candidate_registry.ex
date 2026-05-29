defmodule Chassis.Candidate.Registry.Entry do
  @moduledoc "Candidate registry entry."
  defstruct [
    :candidate_ref,
    :tenant_ref,
    :state,
    :failure_batch_ref,
    :score_matrix_ref,
    :updated_at
  ]

  @type t :: %__MODULE__{}
end

defmodule Chassis.Candidate.Registry.Store.Memory do
  @moduledoc "ETS candidate store."
  @table :chassis_candidate_registry
  def put(entry) do
    ensure_table()
    :ets.insert(@table, {entry.candidate_ref, entry})
    :ok
  end

  def get(ref) do
    ensure_table()

    case :ets.lookup(@table, ref) do
      [{^ref, entry}] -> {:ok, entry}
      [] -> {:error, :not_found}
    end
  end

  def list(_opts \\ []) do
    ensure_table()
    @table |> :ets.tab2list() |> Enum.map(fn {_ref, entry} -> entry end)
  end

  defp ensure_table do
    case :ets.info(@table) do
      :undefined -> :ets.new(@table, [:named_table, :public])
      _info -> @table
    end
  end
end

defmodule Chassis.Candidate.Registry.Store.AshPostgres do
  @moduledoc "Future AshPostgres candidate store facade."
  defdelegate put(entry), to: Chassis.Candidate.Registry.Store.Memory
  defdelegate get(ref), to: Chassis.Candidate.Registry.Store.Memory
  defdelegate list(opts \\ []), to: Chassis.Candidate.Registry.Store.Memory
end

defmodule Chassis.Candidate.Registry do
  @moduledoc "Candidate registry facade."
  def attach(attrs) do
    entry =
      struct(
        Chassis.Candidate.Registry.Entry,
        Map.put_new(attrs, :updated_at, DateTime.utc_now())
      )

    :ok = Chassis.Candidate.Registry.Store.Memory.put(entry)
    {:ok, entry}
  end

  defdelegate get(ref), to: Chassis.Candidate.Registry.Store.Memory
  defdelegate list(opts \\ []), to: Chassis.Candidate.Registry.Store.Memory
end
