defmodule Mix.Tasks.Chassis.Evolution.Status do
  @moduledoc "Show Chassis evolution status."
  use Mix.Task

  @shortdoc "Show Chassis evolution status"

  @impl Mix.Task
  def run(args) do
    {opts, _argv, _invalid} = OptionParser.parse(args, strict: [json: :boolean])
    {:ok, core} = Chassis.Evolution.Core.start_link(name: nil)
    status = Chassis.Evolution.Core.status(core)

    if Keyword.get(opts, :json, false) do
      status |> Chassis.Evolution.Core.jsonable() |> Jason.encode!() |> Mix.shell().info()
    else
      Mix.shell().info("#{status.evolution_run_ref} #{status.state}")
    end
  end
end
