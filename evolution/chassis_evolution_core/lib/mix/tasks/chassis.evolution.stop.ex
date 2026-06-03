defmodule Mix.Tasks.Chassis.Evolution.Stop do
  @moduledoc "Stop a Chassis evolution run."
  use Mix.Task

  @shortdoc "Stop a Chassis evolution run"

  @impl Mix.Task
  def run(args) do
    {opts, _argv, _invalid} =
      OptionParser.parse(args,
        strict: [evolution_ref: :string, reason: :string, json: :boolean]
      )

    {:ok, core} =
      Chassis.Evolution.Core.start_link(
        name: nil,
        evolution_run_ref: Keyword.get(opts, :evolution_ref, "evo:fb:dev:smoke")
      )

    reason = opts |> Keyword.get(:reason, "operator_requested") |> String.to_atom()
    {:ok, :stopped} = Chassis.Evolution.Core.stop(core, reason)
    status = Chassis.Evolution.Core.status(core)

    if Keyword.get(opts, :json, false) do
      status |> Chassis.Evolution.Core.jsonable() |> Jason.encode!() |> Mix.shell().info()
    else
      Mix.shell().info("#{status.evolution_run_ref} #{status.state}")
    end
  end
end
