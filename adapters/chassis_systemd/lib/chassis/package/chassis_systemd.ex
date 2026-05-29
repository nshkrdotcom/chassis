defmodule Chassis.Package.Systemd do
  @moduledoc "Systemd unit and systemctl adapter"

  @spec package_ref() :: String.t()
  def package_ref, do: "chassis_systemd"

  @spec implemented?() :: boolean()
  def implemented?, do: true
end
