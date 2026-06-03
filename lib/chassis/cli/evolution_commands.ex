defmodule Chassis.CLI.Command.Evolution.Fixture do
  @moduledoc "Root CLI command for a Phase 36 evolution conformance scenario."

  alias Chassis.Evolution.Conformance
  alias Chassis.Evolution.Conformance.Evidence

  @spec run([String.t()], map()) :: {:ok, map()} | {:error, term()}
  def run(_positional, switches) do
    case Map.get(switches, :scenario) do
      nil ->
        {:error, %{reason: "missing --scenario"}}

      scenario ->
        opts =
          switches
          |> Map.take([:receipts_dir])
          |> Enum.reject(fn {_key, value} -> is_nil(value) end)

        with {:ok, report} <- Conformance.run(scenario, opts) do
          {:ok, Evidence.jsonable(report)}
        end
    end
  end
end

defmodule Chassis.CLI.Command.Evolution.Proof do
  @moduledoc "Root CLI command for the Phase 36 evolution conformance proof."

  alias Chassis.Evolution.Conformance
  alias Chassis.Evolution.Conformance.Evidence

  @spec run([String.t()], map()) :: {:ok, map()} | {:error, term()}
  def run(_positional, switches) do
    opts =
      switches
      |> Map.take([
        :app,
        :profile,
        :env,
        :fixture,
        :require_trial,
        :require_citadel_consent,
        :require_health_gated_swap,
        :require_rollback_proof
      ])
      |> Map.to_list()

    with {:ok, report} <- Conformance.proof(opts) do
      {:ok, Evidence.jsonable(report)}
    end
  end
end
