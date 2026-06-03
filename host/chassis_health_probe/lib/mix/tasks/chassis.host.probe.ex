defmodule Mix.Tasks.Chassis.Host.Probe do
  @moduledoc "Runs a package-local host health probe smoke."

  use Mix.Task

  @shortdoc "Run host probe smoke"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _rest, _invalid} =
      OptionParser.parse(args,
        strict: [swap_ref: :string, json: :boolean, force: :string]
      )

    swap_ref = Keyword.get(opts, :swap_ref, "swap:dev:smoke")
    force = Keyword.get(opts, :force, "success")

    probe_opts =
      case force do
        "failure" -> [check_failures: %{http_health: :forced_failure}]
        _success -> []
      end

    result =
      Chassis.Health.Probe.run(
        %{
          swap_ref: swap_ref,
          service_ref: "service:smoke",
          prior_artifact_digest: "sha256:prior"
        },
        probe_opts
      )

    emit(result, Keyword.get(opts, :json, false))
  end

  defp emit({:ok, result}, true), do: Mix.shell().info(Jason.encode!(json_safe(result)))
  defp emit({:ok, result}, false), do: Mix.shell().info("outcome=#{result.outcome}")

  defp emit({:error, reason}, true) do
    Mix.shell().info(Jason.encode!(%{error: inspect(reason)}))
    exit({:shutdown, 1})
  end

  defp emit({:error, reason}, false) do
    Mix.shell().error("probe failed: #{inspect(reason)}")
    exit({:shutdown, 1})
  end

  defp json_safe(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
  defp json_safe(%{} = map), do: Map.new(map, fn {key, value} -> {key, json_safe(value)} end)
  defp json_safe(tuple) when is_tuple(tuple), do: tuple |> Tuple.to_list() |> json_safe()
  defp json_safe(list) when is_list(list), do: Enum.map(list, &json_safe/1)
  defp json_safe(atom) when is_atom(atom), do: Atom.to_string(atom)
  defp json_safe(value), do: value
end
