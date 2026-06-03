defmodule Mix.Tasks.Chassis.Model.Fixture do
  use Mix.Task

  @shortdoc "Run one Chassis model asset conformance fixture"

  alias Chassis.ModelAsset.Conformance
  alias Chassis.ModelAsset.Conformance.Evidence

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    {switches, _positional, _invalid} =
      OptionParser.parse(args, strict: [scenario: :string, json: :boolean])

    case Keyword.fetch(switches, :scenario) do
      {:ok, scenario} ->
        scenario
        |> Conformance.run([])
        |> emit(Keyword.get(switches, :json, false))

      :error ->
        Mix.raise("missing --scenario")
    end
  end

  defp emit({:ok, report}, true), do: IO.puts(Jason.encode!(Evidence.jsonable(report)))

  defp emit({:ok, report}, false) do
    IO.puts("scenario: #{report.scenario}")
    IO.puts("status: #{report.status}")
  end

  defp emit({:error, reason}, _json?), do: Mix.raise(inspect(reason))
end
