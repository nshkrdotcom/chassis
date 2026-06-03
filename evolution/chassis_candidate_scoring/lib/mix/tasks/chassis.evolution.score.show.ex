defmodule Mix.Tasks.Chassis.Evolution.Score.Show do
  @moduledoc "Show a Chassis evolution score matrix."
  use Mix.Task

  @shortdoc "Show an evolution score matrix"

  @impl Mix.Task
  def run(args) do
    {opts, _argv, _invalid} =
      OptionParser.parse(args,
        strict: [candidate_ref: :string, json: :boolean]
      )

    candidate_ref = Keyword.get(opts, :candidate_ref, "cand:dev:smoke")

    case Chassis.Candidate.Scoring.show(candidate_ref) do
      {:ok, matrix} ->
        item = Chassis.Candidate.Scoring.jsonable(matrix)

        if Keyword.get(opts, :json, false) do
          Mix.shell().info(Jason.encode!(item))
        else
          Mix.shell().info("#{item.score_matrix_ref} #{item.regression_gate}")
        end

      {:error, reason} ->
        Mix.raise("score show failed: #{inspect(reason)}")
    end
  end
end
