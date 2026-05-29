defmodule Chassis.Package.Ssh do
  @moduledoc "Erlang SSH command and SFTP adapter"

  @spec package_ref() :: String.t()
  def package_ref, do: "chassis_ssh"

  @spec implemented?() :: boolean()
  def implemented?, do: true
end
