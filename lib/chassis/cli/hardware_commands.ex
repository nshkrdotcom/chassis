defmodule Chassis.CLI.Command.Hardware.Validate do
  @moduledoc "Root CLI command for Phase 37 hardware accelerator admission."

  alias Chassis.HardwareGuard

  @spec run([String.t()], map()) :: {:ok, map()} | {:error, term()}
  def run(positional, switches) do
    host_ref = Map.get(switches, :host) || Enum.at(positional, 0)
    runtime_ref = Map.get(switches, :runtime) || Enum.at(positional, 1)

    cond do
      is_nil(host_ref) ->
        {:error, %{reason: "missing --host"}}

      is_nil(runtime_ref) ->
        {:error, %{reason: "missing --runtime"}}

      true ->
        with {:ok, report} <- HardwareGuard.validate(host_ref, runtime_ref) do
          {:ok, HardwareGuard.jsonable(report)}
        end
    end
  end
end
