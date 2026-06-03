defmodule Mix.Tasks.Chassis.Evolution.Candidate.Show do
  @moduledoc "Shows a locally materialized Chassis evolution candidate."
  use Mix.Task

  @shortdoc "Show a Chassis evolution candidate"

  @impl Mix.Task
  def run(args) do
    {opts, _argv, _invalid} =
      OptionParser.parse(args, strict: [candidate_ref: :string, json: :boolean])

    {:ok, fixture_candidate} = Chassis.Candidate.Registry.ensure_fixture_candidate()
    candidate_ref = Keyword.get(opts, :candidate_ref, fixture_candidate.candidate_ref)

    case Chassis.Candidate.Registry.get(candidate_ref) do
      {:ok, entry} ->
        item = Chassis.Candidate.Registry.jsonable_entry(entry)

        if Keyword.get(opts, :json, false) do
          Mix.shell().info(Jason.encode!(item))
        else
          Mix.shell().info("#{item.candidate_ref} #{item.tenant_ref} #{item.last_state}")
        end

      {:error, :not_found} ->
        Mix.raise("candidate not found: #{candidate_ref}")
    end
  end
end
