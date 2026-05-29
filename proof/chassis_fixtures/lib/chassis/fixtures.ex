defmodule Chassis.Fixtures do
  @moduledoc "Canonical topology fixtures."
  def hosts,
    do: [
      %{host_ref: "host:local", region: "local"},
      %{host_ref: "host:gpu-fixture", region: "us-west", gpus: 1}
    ]

  def topology(profile_ref \\ "profile:monolith"),
    do: %{topology_ref: "topology:fixture", profile_ref: profile_ref, hosts: hosts()}
end
