defmodule Chassis.Host.Daemon do
  @moduledoc "Host-resident daemon facade."
  @socket "/var/run/nshkr_chassis_host.sock"
  def status, do: %{state: :running, socket: @socket, mode: "0660"}
  def route(envelope), do: Chassis.Host.Daemon.Router.route(envelope)
end

for name <- [Socket, Identity, Auth, IdempotencyTable, AuthCache] do
  defmodule Module.concat(Chassis.Host.Daemon, name) do
    @moduledoc "Host daemon support module."
    def check(_attrs \\ %{}), do: :ok
  end
end

defmodule Chassis.Host.Daemon.Router do
  @moduledoc "Host daemon envelope router."
  def route(envelope), do: {:ok, %{status: :accepted, envelope: envelope}}
end
