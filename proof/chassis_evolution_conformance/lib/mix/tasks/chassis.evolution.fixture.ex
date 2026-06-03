defmodule Mix.Tasks.Chassis.Evolution.Fixture do
  @moduledoc "Runs one evolution conformance fixture scenario."

  use Mix.Task

  alias Chassis.Evolution.Conformance
  alias Chassis.Evolution.Conformance.Evidence

  @shortdoc "Run an evolution conformance scenario"

  @impl true
  def run(args) do
    {opts, rest, invalid} =
      OptionParser.parse(args,
        strict: [scenario: :string, json: :boolean, receipts_dir: :string]
      )

    reject_extra_args!(rest, invalid)

    scenario =
      Keyword.get(opts, :scenario) ||
        Mix.raise("missing required --scenario <name>")

    run_opts =
      opts
      |> Keyword.take([:receipts_dir])
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)

    case Conformance.run(scenario, run_opts) do
      {:ok, report} -> emit(report, Keyword.get(opts, :json, false))
      {:error, reason} -> Mix.raise("chassis.evolution.fixture failed: #{inspect(reason)}")
    end
  end

  defp emit(report, true) do
    report
    |> Evidence.jsonable()
    |> Jason.encode!()
    |> Mix.shell().info()
  end

  defp emit(report, false) do
    Mix.shell().info("#{report.scenario}: #{String.upcase(to_string(report.final_state))}")
  end

  defp reject_extra_args!([], []), do: :ok

  defp reject_extra_args!(rest, invalid) do
    Mix.raise("invalid chassis.evolution.fixture arguments: #{inspect(rest ++ invalid)}")
  end
end
