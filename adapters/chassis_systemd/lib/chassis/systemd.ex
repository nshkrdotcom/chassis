defmodule Chassis.Adapter.Systemd do
  @moduledoc "Systemd unit and systemctl wrapper."
  @spec unit_file(map()) :: String.t()
  def unit_file(service),
    do:
      "[Unit]\nDescription=#{Map.get(service, :name, "nshkr service")}\n[Service]\nEnvironmentFile=/opt/nshkr/secrets/service.env\nRestart=on-failure\nExecStart=#{Map.get(service, :command, "/bin/true")}\n[Install]\nWantedBy=multi-user.target\n"

  def prepare(payload, _opts \\ []), do: {:ok, Map.put(payload, :unit_file, unit_file(payload))}
  def start(payload, _opts \\ []), do: {:ok, Map.put(payload, :status, :started)}
  def stop(payload, _opts \\ []), do: {:ok, Map.put(payload, :status, :stopped)}
  def health(payload, _opts \\ []), do: {:ok, Map.put(payload, :status, :healthy)}
end

defmodule Chassis.Systemd do
  @moduledoc "Compatibility facade."
end
