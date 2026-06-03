defmodule Chassis.AITrace.Bridge.TestEmitter do
  @moduledoc """
  In-memory span capture used by evolution conformance tests.

  This module is owned by the conformance harness so Phase 36 can validate
  trace DTO posture without mutating the earlier AITrace bridge package.
  """

  @table :chassis_evolution_conformance_aitrace_test_emitter

  @spec emit_span(map(), keyword()) :: :ok
  def emit_span(span, _opts \\ []) when is_map(span) do
    ensure_table()
    :ets.insert(@table, {System.unique_integer([:positive, :monotonic]), span})
    :ok
  end

  @spec reset() :: :ok
  def reset do
    ensure_table()
    :ets.delete_all_objects(@table)
    :ok
  end

  @spec list() :: [map()]
  def list do
    ensure_table()

    @table
    |> :ets.tab2list()
    |> Enum.sort_by(fn {key, _span} -> key end)
    |> Enum.map(fn {_key, span} -> span end)
  end

  defp ensure_table do
    case :ets.whereis(@table) do
      :undefined -> :ets.new(@table, [:named_table, :public, :ordered_set])
      table -> table
    end
  end
end
