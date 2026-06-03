defmodule Mix.Tasks.Chassis.Host.Daemon.Socket.Check do
  @moduledoc "Check host-daemon socket configuration."
  use Mix.Task

  @shortdoc "Check host-daemon socket configuration"

  @impl true
  def run(argv) do
    Mix.Task.run("app.start")

    {_opts, _positional, _invalid} =
      OptionParser.parse(argv, strict: [json: :boolean], aliases: [])

    status = Chassis.Host.Daemon.status()

    %{
      state: :ok,
      socket_path: status.socket_path,
      socket_mode: status.socket_mode,
      socket_owner: status.socket_owner,
      peer_acl: status.peer_acl
    }
    |> plain()
    |> Jason.encode!()
    |> Mix.shell().info()
  end

  defp plain(map) when is_map(map), do: Map.new(map, fn {key, value} -> {key, plain(value)} end)
  defp plain(list) when is_list(list), do: Enum.map(list, &plain/1)
  defp plain(value) when is_atom(value), do: Atom.to_string(value)
  defp plain(value), do: value
end
