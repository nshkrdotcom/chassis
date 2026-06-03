defmodule Mix.Tasks.Chassis.Evolution.Batches do
  @moduledoc "Lists locally materialized Chassis evolution failure batches."
  use Mix.Task

  @shortdoc "List Chassis evolution failure batches"

  @impl Mix.Task
  def run(args) do
    {opts, _argv, _invalid} = OptionParser.parse(args, strict: [json: :boolean])
    {:ok, _batch} = Chassis.FailureBatches.ensure_fixture_batch()

    items =
      Enum.map(Chassis.FailureBatches.list_batches(), &Chassis.FailureBatches.jsonable_batch/1)

    if Keyword.get(opts, :json, false) do
      Mix.shell().info(Jason.encode!(%{items: items}))
    else
      Enum.each(items, &Mix.shell().info(&1.failure_batch_ref))
    end
  end
end
