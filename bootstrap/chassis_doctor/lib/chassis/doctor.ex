defmodule Chassis.Doctor do
  @moduledoc "Diagnostics facade."
  @spec run(keyword()) :: {:ok, map()}
  def run(opts \\ []), do: {:ok, %{status: :healthy, opts: opts}}
end

defmodule Chassis.Doctor.NodeDiagnostics do
  @moduledoc "Node diagnostics."
  def check(node_ref), do: {:ok, %{node_ref: node_ref, status: :healthy}}
end

defmodule Chassis.Doctor.MeshDiagnostics do
  @moduledoc "Mesh diagnostics."
  def check(mesh_ref), do: {:ok, %{mesh_ref: mesh_ref, status: :healthy}}
end

defmodule Chassis.Doctor.HostDiagnostics do
  @moduledoc "Host diagnostics."
  def check(host_ref), do: {:ok, %{host_ref: host_ref, status: :online}}
end
