defmodule Chassis.CLI.Command.Tensor.Reload do
  @moduledoc "Root CLI command for Phase 40 tensor patch reload."

  alias Chassis.Tensor.Reload

  @spec run([String.t()], map()) :: {:ok, map()} | {:error, term()}
  def run(positional, switches) do
    runtime_ref = Map.get(switches, :runtime) || Enum.at(positional, 0)
    patch_ref = Map.get(switches, :patch) || Enum.at(positional, 1)

    cond do
      is_nil(runtime_ref) ->
        {:error, %{reason: "missing --runtime"}}

      is_nil(patch_ref) ->
        {:error, %{reason: "missing --patch"}}

      true ->
        with {:ok, report} <- Reload.reload(runtime_ref, patch_ref) do
          {:ok, Reload.jsonable(report)}
        end
    end
  end
end

defmodule Chassis.CLI.Command.Tensor.Rollback do
  @moduledoc "Root CLI command for Phase 40 tensor patch rollback."

  alias Chassis.Tensor.Reload

  @spec run([String.t()], map()) :: {:ok, map()} | {:error, term()}
  def run(positional, switches) do
    runtime_ref = Map.get(switches, :runtime) || Enum.at(positional, 0)
    patch_ref = Map.get(switches, :patch) || Enum.at(positional, 1)

    cond do
      is_nil(runtime_ref) ->
        {:error, %{reason: "missing --runtime"}}

      is_nil(patch_ref) ->
        {:error, %{reason: "missing --patch"}}

      true ->
        with {:ok, report} <- Reload.rollback(runtime_ref, patch_ref) do
          {:ok, Reload.jsonable(report)}
        end
    end
  end
end
