defmodule Chassis.Evolution.Receipts.Store.Memory do
  @moduledoc "Evolution receipt memory store."
  @table :chassis_evolution_receipts
  def put(receipt) do
    ensure_table()

    ref =
      Map.get(
        receipt,
        :receipt_ref,
        "receipt:evolution:" <> Integer.to_string(System.unique_integer([:positive]))
      )

    receipt = Map.put(receipt, :receipt_ref, ref)
    :ets.insert(@table, {ref, receipt})
    {:ok, receipt}
  end

  def list(_opts \\ []) do
    ensure_table()
    @table |> :ets.tab2list() |> Enum.map(fn {_ref, receipt} -> receipt end)
  end

  defp ensure_table do
    case :ets.info(@table) do
      :undefined -> :ets.new(@table, [:named_table, :public])
      _info -> @table
    end
  end
end

defmodule Chassis.Evolution.Receipts.Store.AshPostgres do
  @moduledoc "Future AshPostgres evolution receipt store facade."
  defdelegate put(receipt), to: Chassis.Evolution.Receipts.Store.Memory
  defdelegate list(opts \\ []), to: Chassis.Evolution.Receipts.Store.Memory
end

for name <- [
      FailureBatchRecord,
      CandidatePatchRecord,
      CodingAgentRunRecord,
      TrialRunRecord,
      ScoreMatrixRecord,
      PromotionIntentRecord,
      PromotionRecord,
      SwapRecord,
      EvolutionRollbackRecord,
      OperatorConsentRecord,
      EvolutionStartRecord,
      EvolutionStopRecord
    ] do
  defmodule Module.concat(Chassis.Evolution.Receipts, name) do
    @moduledoc "Evolution receipt record."
    defstruct [:receipt_ref, :tenant_ref, :candidate_ref, :payload, :inserted_at]
    @type t :: %__MODULE__{}
    def put(attrs),
      do:
        Chassis.Evolution.Receipts.Store.Memory.put(
          Map.merge(%{record_module: inspect(__MODULE__), inserted_at: DateTime.utc_now()}, attrs)
        )
  end
end
