defmodule Mix.Tasks.Chassis.Proof.Run do
  @moduledoc "Run Chassis StackLab conformance proofs."
  use Mix.Task

  alias Chassis.StackLab.Bridge.RunConformance

  @shortdoc "Run Chassis StackLab conformance proofs"

  @impl true
  def run(args) do
    {opts, _rest, _invalid} =
      OptionParser.parse(args,
        strict: [tag: :string, json: :boolean, all: :boolean, proof: :keep],
        aliases: [p: :proof]
      )

    proof_refs =
      case Keyword.get_values(opts, :proof) do
        [] -> :all
        refs -> refs
      end

    run_opts = [tag: Keyword.get(opts, :tag, "chassis"), proof_refs: proof_refs]

    case RunConformance.run(run_opts) do
      {:ok, report} ->
        emit(report, Keyword.get(opts, :json, false))

      {:error, reason} ->
        Mix.raise("chassis.proof.run failed: #{inspect(reason)}")
    end
  end

  defp emit(report, true) do
    report
    |> RunConformance.jsonable_report()
    |> Jason.encode!()
    |> Mix.shell().info()
  end

  defp emit(report, false) do
    Enum.each(report.proofs, fn proof ->
      Mix.shell().info("#{proof.name}: #{String.upcase(to_string(proof.status))}")
    end)
  end
end
