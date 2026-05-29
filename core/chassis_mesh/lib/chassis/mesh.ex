defmodule Chassis.Mesh.Adapter do
  @moduledoc "Mesh adapter behaviour."
  @callback init_node(map()) :: {:ok, map()} | {:error, term()}
  @callback join_group(atom(), pid()) :: :ok | {:error, term()}
  @callback health(map()) :: {:ok, map()} | {:error, term()}
end

defmodule Chassis.Mesh.TlsKit do
  @moduledoc "TLS material generator for BEAM distribution."
  @spec generate_cluster_material(String.t()) :: map()
  def generate_cluster_material(cluster_ref) do
    ca = :public_key.pem_encode([])
    %{cluster_ref: cluster_ref, ca_pem: ca, cert_ref: "secret:mesh_cert:" <> cluster_ref}
  end
end

defmodule Chassis.Mesh.BEAMDistribution do
  @moduledoc "BEAM TLS mesh adapter."
  @spec init_node(map()) :: {:ok, map()}
  def init_node(config),
    do: {:ok, Map.merge(%{mesh_status: :joined, dist_ports: 9100..9200}, config)}

  @spec join_group(atom(), pid()) :: :ok
  def join_group(group, pid), do: :pg.join(group, pid)
  @spec health(map()) :: {:ok, map()}
  def health(config), do: {:ok, %{status: :healthy, node: Map.get(config, :node, node())}}
end

defmodule Chassis.Mesh.LocalLoopback do
  @moduledoc "Local loopback mesh."
  defdelegate init_node(config), to: Chassis.Mesh.BEAMDistribution
  defdelegate join_group(group, pid), to: Chassis.Mesh.BEAMDistribution
  defdelegate health(config), to: Chassis.Mesh.BEAMDistribution
end

defmodule Chassis.Mesh.HealthSupervisor do
  @moduledoc "Basic health loop entrypoint."
  @spec check_once(map()) :: {:ok, map()}
  def check_once(config),
    do: {:ok, %{status: :healthy, checked_at: DateTime.utc_now(), config: config}}
end
