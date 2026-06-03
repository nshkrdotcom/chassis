defmodule Mix.Tasks.Chassis.Evolution.Batch.Show do
  @moduledoc "Shows a locally materialized Chassis evolution failure batch."
  use Mix.Task

  @shortdoc "Show a Chassis evolution failure batch"

  @impl Mix.Task
  def run(args) do
    {opts, _argv, _invalid} =
      OptionParser.parse(args, strict: [batch_ref: :string, json: :boolean])

    {:ok, fixture_batch} = Chassis.FailureBatches.ensure_fixture_batch()
    batch_ref = Keyword.get(opts, :batch_ref, fixture_batch.failure_batch_ref)

    case Chassis.FailureBatches.get_batch(batch_ref) do
      {:ok, batch} ->
        item = Chassis.FailureBatches.jsonable_batch(batch)

        if Keyword.get(opts, :json, false) do
          Mix.shell().info(Jason.encode!(item))
        else
          Mix.shell().info(
            "#{item.failure_batch_ref} #{item.tenant_ref} #{item.installation_ref}"
          )
        end

      {:error, :not_found} ->
        Mix.raise("failure batch not found: #{batch_ref}")
    end
  end
end
