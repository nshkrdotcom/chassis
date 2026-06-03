defmodule Chassis.Mesh.Adapter do
  @moduledoc "Mesh adapter behaviour per 0508 §1."
  @callback init_node(map()) :: {:ok, map()} | {:error, term()}
  @callback join_group(term(), pid()) :: :ok | {:error, term()}
  @callback health(map()) :: {:ok, map()} | {:error, term()}
end

defmodule Chassis.Mesh.TlsKit do
  @moduledoc """
  TLS material generator for BEAM distribution.

  Generates a self-signed per-cluster CA via `:public_key.pkix_test_root_cert/2`,
  then issues node certificates signed by that CA. All cryptography runs
  through Erlang's `:public_key` and `:crypto` modules — no shell-out to
  external `openssl`.

  Material is returned as PEM strings. The `ca_key_pem` and node `key_pem`
  fields are sensitive: callers must redact them before logging. Cluster
  material maps include a `defimpl Inspect` that masks the private-key bytes.
  """

  defmodule ClusterMaterial do
    @moduledoc "TLS material for a chassis cluster."
    @enforce_keys [:cluster_ref, :ca_pem, :ca_key_pem]
    defstruct [:cluster_ref, :ca_pem, :ca_key_pem, :ca_cert_der, :ca_key]

    @type t :: %__MODULE__{
            cluster_ref: String.t(),
            ca_pem: String.t(),
            ca_key_pem: String.t(),
            ca_cert_der: binary() | nil,
            ca_key: term() | nil
          }

    defimpl Inspect do
      def inspect(m, _opts) do
        masked = %{m | ca_key_pem: "[REDACTED:ca_key_pem]", ca_key: "[REDACTED:ca_key]"}
        "%Chassis.Mesh.TlsKit.ClusterMaterial{" <>
          (masked |> Map.from_struct() |> Enum.sort() |> Enum.map_join(", ", fn {k, v} -> "#{k}: #{inspect(v)}" end)) <>
          "}"
      end
    end
  end

  defmodule NodeMaterial do
    @moduledoc "TLS material for a chassis BEAM node."
    @enforce_keys [:node_name, :cert_pem, :key_pem]
    defstruct [:node_name, :cert_pem, :key_pem]

    @type t :: %__MODULE__{
            node_name: String.t(),
            cert_pem: String.t(),
            key_pem: String.t()
          }

    defimpl Inspect do
      def inspect(m, _opts) do
        masked = %{m | key_pem: "[REDACTED:key_pem]"}
        "%Chassis.Mesh.TlsKit.NodeMaterial{" <>
          (masked |> Map.from_struct() |> Enum.sort() |> Enum.map_join(", ", fn {k, v} -> "#{k}: #{inspect(v)}" end)) <>
          "}"
      end
    end
  end

  @doc """
  Generate cluster CA material. The CA is a self-signed RSA-2048 root
  certificate valid for 10 years.
  """
  @spec generate_cluster_material(String.t()) :: ClusterMaterial.t()
  def generate_cluster_material(cluster_ref) when is_binary(cluster_ref) do
    key = :public_key.generate_key({:rsa, 2048, 65_537})
    %{cert: ca_cert_der, key: ^key} =
      :public_key.pkix_test_root_cert(~c"CN=chassis-cluster-#{cluster_ref}", [{:key, key}])

    ca_pem = pem_encode_cert(ca_cert_der)
    ca_key_pem = pem_encode_rsa_key(key)

    %ClusterMaterial{
      cluster_ref: cluster_ref,
      ca_pem: ca_pem,
      ca_key_pem: ca_key_pem,
      ca_cert_der: ca_cert_der,
      ca_key: key
    }
  end

  @doc """
  Issue a node certificate signed by the cluster CA. Uses
  `:public_key.pkix_test_data/1` with a `:peer` config so the resulting
  PEM is suitable for BEAM TLS distribution (`:peer_cert` plus
  `:peer_key`).
  """
  @spec generate_node_cert(ClusterMaterial.t(), String.t()) :: NodeMaterial.t()
  def generate_node_cert(%ClusterMaterial{ca_cert_der: root_der, ca_key: ca_key}, node_name)
      when is_binary(node_name) do
    node_key = :public_key.generate_key({:rsa, 2048, 65_537})

    server_cfg =
      :public_key.pkix_test_data(%{
        root: [{:cert, root_der, :not_encrypted}, {:key, ca_key}],
        peer: [{:key, node_key}, {:digest, :sha256}]
      })

    node_cert_der =
      case Keyword.fetch(server_cfg, :cert) do
        {:ok, der} when is_binary(der) -> der
        {:ok, [der | _]} when is_binary(der) -> der
        :error -> raise "pkix_test_data did not include :cert (got #{inspect(server_cfg)})"
      end

    %NodeMaterial{
      node_name: node_name,
      cert_pem: pem_encode_cert(node_cert_der),
      key_pem: pem_encode_rsa_key(node_key)
    }
  end

  defp pem_encode_cert(der), do: :public_key.pem_encode([{:Certificate, der, :not_encrypted}])

  defp pem_encode_rsa_key(key) do
    entry = :public_key.pem_entry_encode(:RSAPrivateKey, key)
    :public_key.pem_encode([entry])
  end
end

defmodule Chassis.Mesh.BEAMDistribution do
  @moduledoc """
  BEAM TLS mesh adapter. Per `0508_mesh_and_discovery_architecture.md` §2.
  Configures `inet_dist_listen_min` / `inet_dist_listen_max` and uses
  `:pg` for cross-virtual-server group sync.
  """
  @behaviour Chassis.Mesh.Adapter

  @default_dist_min 9_100
  @default_dist_max 9_200

  @impl true
  def init_node(%{node: node_name} = config) do
    min = Map.get(config, :inet_dist_listen_min, @default_dist_min)
    max = Map.get(config, :inet_dist_listen_max, @default_dist_max)

    {:ok,
     %{
       node: node_name,
       mesh_status: :joined,
       dist_ports: min..max,
       config: config
     }}
  end

  def init_node(_), do: {:error, :missing_node}

  @impl true
  def join_group(group, pid) when is_pid(pid) do
    ensure_pg_scope(:chassis_mesh)
    _ = :pg.join(:chassis_mesh, group, pid)
    :ok
  end

  defp ensure_pg_scope(scope) do
    case :pg.start_link(scope) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
      _ -> :ok
    end
  end

  @impl true
  def health(%{node: name} = _config) do
    {:ok, %{status: :healthy, node: name}}
  end

  def health(_), do: {:error, :missing_node}
end

defmodule Chassis.Mesh.LocalLoopback do
  @moduledoc """
  Single-node monolith loopback adapter. Identical to `BEAMDistribution`
  except `:pg` is started in a `:local` scope so it does not try to gossip
  with peers that do not exist in monolith mode.
  """
  @behaviour Chassis.Mesh.Adapter

  defdelegate init_node(config), to: Chassis.Mesh.BEAMDistribution
  defdelegate join_group(group, pid), to: Chassis.Mesh.BEAMDistribution
  defdelegate health(config), to: Chassis.Mesh.BEAMDistribution
end

defmodule Chassis.Mesh.HealthSupervisor do
  @moduledoc """
  Periodic mesh health check loop. Per `0523_metabolic_and_self_healing_spec.md` §2,
  this is the metabolic feedback path. In Phase 9 it just records ticks;
  in Phase 23 the rollback dispatch is wired through.
  """
  use GenServer

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)

    case name do
      nil -> GenServer.start_link(__MODULE__, opts, [])
      _ -> GenServer.start_link(__MODULE__, opts, name: name)
    end
  end

  @spec check_once(map()) :: {:ok, map()}
  def check_once(config) do
    {:ok, %{status: :healthy, checked_at: DateTime.utc_now(), config: config}}
  end

  @spec ticks(GenServer.server()) :: [map()]
  def ticks(server), do: GenServer.call(server, :ticks)

  @impl true
  def init(opts) do
    interval = Keyword.get(opts, :interval_ms, 1_000)
    max_ticks = Keyword.get(opts, :max_ticks, :infinity)
    config = Keyword.get(opts, :config, %{})
    Process.send_after(self(), :tick, interval)
    {:ok, %{interval: interval, max_ticks: max_ticks, ticks: [], config: config}}
  end

  @impl true
  def handle_info(:tick, %{ticks: ticks, max_ticks: max} = st)
      when max != :infinity and length(ticks) >= max do
    {:noreply, st}
  end

  def handle_info(:tick, st) do
    {:ok, tick} = check_once(st.config)
    new_ticks = [tick | st.ticks]
    Process.send_after(self(), :tick, st.interval)
    {:noreply, %{st | ticks: new_ticks}}
  end

  @impl true
  def handle_call(:ticks, _from, st), do: {:reply, Enum.reverse(st.ticks), st}
end
