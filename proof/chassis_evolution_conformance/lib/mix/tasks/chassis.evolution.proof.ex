defmodule Mix.Tasks.Chassis.Evolution.Proof do
  @moduledoc "Runs the full evolution conformance proof harness."

  use Mix.Task

  alias Chassis.Evolution.Conformance
  alias Chassis.Evolution.Conformance.Evidence

  @shortdoc "Run evolution conformance proof"

  @impl true
  def run(args) do
    {opts, rest, invalid} =
      OptionParser.parse(args,
        strict: [
          app: :string,
          profile: :string,
          env: :string,
          fixture: :string,
          require_trial: :boolean,
          require_citadel_consent: :boolean,
          require_health_gated_swap: :boolean,
          require_rollback_proof: :boolean,
          json: :boolean
        ],
        aliases: []
      )

    reject_extra_args!(rest, invalid)

    case Conformance.proof(opts) do
      {:ok, report} -> emit(report, Keyword.get(opts, :json, false))
      {:error, reason} -> Mix.raise("chassis.evolution.proof failed: #{inspect(reason)}")
    end
  end

  defp emit(report, true) do
    report
    |> Evidence.jsonable()
    |> Jason.encode!()
    |> Mix.shell().info()
  end

  defp emit(report, false) do
    Mix.shell().info("chassis_evolution: PASS #{report.passed}/#{report.passed + report.failed}")
  end

  defp reject_extra_args!([], []), do: :ok

  defp reject_extra_args!(rest, invalid) do
    Mix.raise("invalid chassis.evolution.proof arguments: #{inspect(rest ++ invalid)}")
  end
end
