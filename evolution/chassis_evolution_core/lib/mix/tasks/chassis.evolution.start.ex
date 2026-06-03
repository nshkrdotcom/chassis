defmodule Mix.Tasks.Chassis.Evolution.Start do
  @moduledoc "Start a Chassis evolution run."
  use Mix.Task

  @shortdoc "Start a Chassis evolution run"

  @impl Mix.Task
  def run(args) do
    {opts, _argv, _invalid} =
      OptionParser.parse(args,
        strict: [batch_ref: :string, evolution_ref: :string, json: :boolean]
      )

    failure_batch_ref = Keyword.get(opts, :batch_ref, "fb:dev:smoke")

    {:ok, core} =
      Chassis.Evolution.Core.start_link(
        name: nil,
        failure_batch_ref: failure_batch_ref,
        evolution_run_ref: Keyword.get(opts, :evolution_ref)
      )

    emit(Chassis.Evolution.Core.status(core), Keyword.get(opts, :json, false))
  end

  defp emit(status, true) do
    status |> Chassis.Evolution.Core.jsonable() |> Jason.encode!() |> Mix.shell().info()
  end

  defp emit(status, false) do
    Mix.shell().info("#{status.evolution_run_ref} #{status.state}")
  end
end
