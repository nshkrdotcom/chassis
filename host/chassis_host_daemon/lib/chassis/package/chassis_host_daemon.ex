defmodule Chassis.Package.HostDaemon do
  @moduledoc "Host-resident daemon and Unix socket routing"

  @spec package_ref() :: String.t()
  def package_ref, do: "chassis_host_daemon"

  @spec implemented?() :: boolean()
  def implemented?, do: true
end
