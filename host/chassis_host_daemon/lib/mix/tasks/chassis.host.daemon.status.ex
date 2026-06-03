defmodule Mix.Tasks.Chassis.Host.Daemon.Status do
  @moduledoc "Print host-daemon status."
  use Mix.Task

  @shortdoc "Print host-daemon status"

  @impl true
  def run(argv) do
    Mix.Task.run("app.start")

    {_opts, _positional, _invalid} =
      OptionParser.parse(argv, strict: [json: :boolean], aliases: [])

    Chassis.Host.Daemon.status()
    |> plain()
    |> Jason.encode!()
    |> Mix.shell().info()
  end

  defp plain(map) when is_map(map), do: Map.new(map, fn {key, value} -> {key, plain(value)} end)
  defp plain(list) when is_list(list), do: Enum.map(list, &plain/1)
  defp plain(value) when is_atom(value), do: Atom.to_string(value)
  defp plain(value), do: value
end
