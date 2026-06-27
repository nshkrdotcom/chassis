defmodule Chassis.CLI.Runtime do
  @moduledoc """
  Root CLI runtime state for command modules that need local stores.

  The root CLI stays a dynamic dispatcher. This module only owns the process
  names used by root-loaded command modules so they can exercise package-owned
  behavior without static payloads.
  """

  @registry __MODULE__.AppRegistry
  @receipts_store __MODULE__.ReceiptsStore
  @fence_store __MODULE__.FenceStore
  @checkpoint_store __MODULE__.CheckpointStore
  @outbox __MODULE__.Outbox

  @spec registry() :: atom()
  def registry, do: ensure_started(@registry, Chassis.AppRegistry)

  @spec receipts_store() :: atom()
  def receipts_store, do: ensure_started(@receipts_store, Chassis.Receipts.Store.Memory)

  @spec fence_store() :: atom()
  def fence_store, do: ensure_started(@fence_store, Chassis.StackManager.FenceStore)

  @spec checkpoint_store() :: atom()
  def checkpoint_store,
    do: ensure_started(@checkpoint_store, Chassis.StackManager.CheckpointStore)

  @spec outbox() :: atom()
  def outbox, do: ensure_started(@outbox, Chassis.Mezzanine.Bridge.Outbox)

  @spec reset!() :: :ok
  def reset! do
    for name <- [@registry, @receipts_store, @fence_store, @checkpoint_store, @outbox] do
      case Process.whereis(name) do
        nil ->
          :ok

        pid ->
          Process.exit(pid, :kill)
          wait_down(name)
      end
    end

    :ok
  end

  defp ensure_started(name, module) do
    case Process.whereis(name) do
      nil ->
        case module.start_link(name: name) do
          {:ok, _pid} -> name
          {:error, {:already_started, _pid}} -> name
        end

      _pid ->
        name
    end
  end

  defp wait_down(name) do
    if Process.whereis(name) do
      Process.sleep(5)
      wait_down(name)
    else
      :ok
    end
  end
end
