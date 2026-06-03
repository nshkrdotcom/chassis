defmodule Mix.Tasks.Chassis.Host.Swap do
  @moduledoc "Runs a package-local host swap smoke through Chassis.Swap.Supervisor."

  use Mix.Task

  @shortdoc "Run host swap smoke"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _rest, _invalid} =
      OptionParser.parse(args,
        strict: [candidate_ref: :string, swap_ref: :string, json: :boolean]
      )

    candidate_ref = Keyword.get(opts, :candidate_ref, "cand:dev:smoke")
    swap_ref = Keyword.get(opts, :swap_ref, "swap:#{candidate_ref}")

    result =
      candidate_ref
      |> Chassis.Swap.Supervisor.smoke_preconditions()
      |> Chassis.Swap.Supervisor.execute_swap(
        Chassis.Swap.Supervisor.smoke_opts(candidate_ref: candidate_ref, swap_ref: swap_ref)
      )

    emit(result, Keyword.get(opts, :json, false))
  end

  defp emit({:ok, result}, true), do: Mix.shell().info(Jason.encode!(json_safe(result)))
  defp emit({:ok, result}, false), do: Mix.shell().info("swap_ref=#{result.swap_ref}")

  defp emit({:error, reason}, true) do
    Mix.shell().info(Jason.encode!(%{error: inspect(reason)}))
    exit({:shutdown, 1})
  end

  defp emit({:error, reason}, false) do
    Mix.shell().error("swap failed: #{inspect(reason)}")
    exit({:shutdown, 1})
  end

  defp json_safe(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
  defp json_safe(%{} = map), do: Map.new(map, fn {key, value} -> {key, json_safe(value)} end)
  defp json_safe(list) when is_list(list), do: Enum.map(list, &json_safe/1)
  defp json_safe(atom) when is_atom(atom), do: Atom.to_string(atom)
  defp json_safe(value), do: value
end
