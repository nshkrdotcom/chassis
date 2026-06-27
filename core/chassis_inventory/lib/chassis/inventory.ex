defmodule Chassis.Inventory do
  @moduledoc """
  Inventory helpers. The fixture set lives in `proof/chassis_fixtures` after
  Phase 21; until then a tiny local fixture list is kept here only to
  bootstrap unit tests of the `StaticDiscovery` JSON-reading path.
  """

  @doc """
  Local two-host fixture useful only for early phases before
  `proof/chassis_fixtures` lands. Production code MUST use
  `Chassis.Inventory.StaticDiscovery.discover_hosts(path: ...)`.
  """
  @spec fixture_hosts() :: [map()]
  def fixture_hosts do
    [
      %{
        host_ref: "host:local",
        provider: :local,
        region: "local",
        resources: %{cpu_cores: 8, ram_gb: 32, gpus: 0, disk_gb: 512},
        tenant_refs: ["tenant:dev"]
      },
      %{
        host_ref: "host:gpu-fixture",
        provider: :fixture,
        region: "us-west",
        resources: %{cpu_cores: 16, ram_gb: 64, gpus: 1, disk_gb: 1024},
        tenant_refs: ["tenant:dev"]
      }
    ]
  end
end

defmodule Chassis.Inventory.PhysicalHost do
  @moduledoc "Tenant-filterable physical host descriptor."
  defstruct [:host_ref, :provider, :region, :hostname, resources: %{}, tenant_refs: []]

  @type t :: %__MODULE__{
          host_ref: String.t() | nil,
          provider: atom() | nil,
          region: String.t() | nil,
          hostname: String.t() | nil,
          resources: map(),
          tenant_refs: [String.t()]
        }
end

defmodule Chassis.Inventory.CapacityMap do
  @moduledoc """
  Allocated vs total resource accounting for a single host. `available/1`
  returns the remainder; `allocate/2` and `release/2` are pure transitions
  that refuse over-commit.
  """
  defstruct [:host_ref, total: %{}, allocated: %{}]
  @type t :: %__MODULE__{host_ref: String.t() | nil, total: map(), allocated: map()}

  @spec available(t()) :: map()
  def available(%__MODULE__{total: t, allocated: a}) do
    Map.new(t, fn {k, total} -> {k, total - Map.get(a, k, 0)} end)
  end

  @spec allocate(t(), map()) :: {:ok, t()} | {:error, {:would_overcommit, atom()}}
  def allocate(%__MODULE__{} = cap, request) when is_map(request) do
    Enum.reduce_while(request, {:ok, cap}, fn {k, v}, {:ok, acc} ->
      allocated = Map.get(acc.allocated, k, 0) + v
      total = Map.get(acc.total, k, 0)

      if allocated > total do
        {:halt, {:error, {:would_overcommit, k}}}
      else
        {:cont, {:ok, %{acc | allocated: Map.put(acc.allocated, k, allocated)}}}
      end
    end)
  end

  @spec release(t(), map()) :: {:ok, t()}
  def release(%__MODULE__{} = cap, request) when is_map(request) do
    new_allocated =
      Enum.reduce(request, cap.allocated, fn {k, v}, acc ->
        next = max(Map.get(acc, k, 0) - v, 0)
        Map.put(acc, k, next)
      end)

    {:ok, %{cap | allocated: new_allocated}}
  end
end

defmodule Chassis.Inventory.GpuInventory do
  @moduledoc "GPU vendor/model/VRAM inventory."
  defstruct [:host_ref, :vendor, :model, vram_gb: 0, free_count: 0]

  @type t :: %__MODULE__{
          host_ref: String.t() | nil,
          vendor: String.t() | nil,
          model: String.t() | nil,
          vram_gb: non_neg_integer(),
          free_count: non_neg_integer()
        }
end

defmodule Chassis.Inventory.PlacementValidator do
  @moduledoc """
  Validates that a host can accommodate a placement request. Returns `:ok`
  or `{:error, <reason_atom>}` for the first constraint that fails. Reasons:
  `:cpu_unavailable`, `:memory_unavailable`, `:gpu_unavailable`, `:disk_unavailable`.
  """
  @spec check(map(), map()) :: :ok | {:error, atom()}
  def check(host, request) do
    resources = Map.get(host, :resources, %{})

    cond do
      Map.get(request, :gpus, 0) > Map.get(resources, :gpus, 0) ->
        {:error, :gpu_unavailable}

      Map.get(request, :cpu_cores, 0) > Map.get(resources, :cpu_cores, 0) ->
        {:error, :cpu_unavailable}

      Map.get(request, :ram_gb, 0) > Map.get(resources, :ram_gb, 0) ->
        {:error, :memory_unavailable}

      Map.get(request, :disk_gb, 0) > Map.get(resources, :disk_gb, 0) ->
        {:error, :disk_unavailable}

      true ->
        :ok
    end
  end
end

defmodule Chassis.Inventory.Discovery do
  @moduledoc "Host discovery behaviour."
  @callback discover_hosts(keyword()) :: {:ok, [map()]} | {:error, term()}
end

defmodule Chassis.Inventory.StaticDiscovery do
  @moduledoc """
  Reads hosts from a JSON file (default `~/.config/chassis/hosts.json`, per
  `0508_mesh_and_discovery_architecture.md` §5). Supports `tenant_ref:`
  filtering. Returns canonical errors on missing file or malformed JSON.

  `host_ref` is the canonical join key. IPs MUST NOT be used as the join key.
  """
  @behaviour Chassis.Inventory.Discovery

  @default_path "~/.config/chassis/hosts.json"
  @provider_atoms %{
    "local" => :local,
    "fixture" => :fixture,
    "static" => :static,
    "linode" => :linode,
    "digital_ocean" => :digital_ocean,
    "hetzner" => :hetzner,
    "runpod" => :runpod,
    "vast_ai" => :vast_ai
  }
  @resource_atoms %{
    "cpu_cores" => :cpu_cores,
    "ram_gb" => :ram_gb,
    "gpus" => :gpus,
    "disk_gb" => :disk_gb
  }

  @impl true
  @spec discover_hosts(keyword()) :: {:ok, [map()]} | {:error, term()}
  def discover_hosts(opts \\ []) do
    path = opts |> Keyword.get(:path, @default_path) |> Path.expand()

    with {:ok, body} <- read_file(path),
         {:ok, {hosts_payload, tenant_ref}} <- decode_json(body) do
      opts = Keyword.put_new(opts, :tenant_ref, tenant_ref)
      hosts = hosts_payload |> Enum.map(&normalize_host/1) |> filter_by_tenant(opts)
      {:ok, hosts}
    end
  end

  defp read_file(path) do
    case File.read(path) do
      {:ok, body} -> {:ok, body}
      {:error, reason} -> {:error, reason}
    end
  end

  defp decode_json(body) do
    case Jason.decode(body) do
      {:ok, parsed} when is_list(parsed) ->
        {:ok, {parsed, nil}}

      {:ok, %{"hosts" => hosts} = parsed} when is_list(hosts) ->
        {:ok, {hosts, parsed["tenant_ref"]}}

      {:ok, _other} ->
        {:error, {:json_decode, :not_a_host_list}}

      {:error, reason} ->
        {:error, {:json_decode, reason}}
    end
  end

  defp normalize_host(host) when is_map(host) do
    %{
      host_ref: host["host_ref"],
      provider: normalize_provider(host["provider"]),
      region: host["region"],
      hostname: host["hostname"],
      ip_address: host["ip_address"],
      resources: normalize_resources(host["resources"] || %{}),
      tenant_refs: host["tenant_refs"] || []
    }
  end

  defp normalize_provider(nil), do: nil
  defp normalize_provider(value) when is_atom(value), do: value

  defp normalize_provider(value) when is_binary(value),
    do: Map.get(@provider_atoms, value, value)

  defp normalize_resources(map) when is_map(map) do
    Map.new(map, fn {k, v} ->
      key =
        cond do
          is_atom(k) -> k
          is_binary(k) -> Map.get(@resource_atoms, k, k)
          true -> k
        end

      {key, v}
    end)
  end

  defp filter_by_tenant(hosts, opts) do
    case Keyword.get(opts, :tenant_ref) do
      nil -> hosts
      tenant_ref -> Enum.filter(hosts, &(tenant_ref in Map.get(&1, :tenant_refs, [])))
    end
  end
end

defmodule Chassis.Inventory.DynamicDiscovery do
  @moduledoc """
  Provider-routed dynamic discovery facade.

  Per `0541_implementation_readiness_corrections.md` §1 row 4 and
  `0537` §3 Phase 8 schedule, every provider returns
  `{:error, {:not_implemented, __MODULE__}}` in Phase 3. Phase 8 lands
  real HTTP clients for `:linode`, `:digital_ocean`, `:hetzner`, `:runpod`,
  and `:vast_ai`.

  Calling `discover_hosts/1` without an explicit `provider:` option returns
  `{:error, :missing_provider}` — the facade does NOT silently fall through
  to a static fixture (that was the static_cli_path antipattern removed in
  Phase 0).
  """
  @behaviour Chassis.Inventory.Discovery

  @providers %{
    linode: Chassis.Inventory.DynamicDiscovery.Linode,
    digital_ocean: Chassis.Inventory.DynamicDiscovery.DigitalOcean,
    hetzner: Chassis.Inventory.DynamicDiscovery.Hetzner,
    runpod: Chassis.Inventory.DynamicDiscovery.RunPod,
    vast_ai: Chassis.Inventory.DynamicDiscovery.VastAi
  }

  @impl true
  @spec discover_hosts(keyword()) :: {:ok, [map()]} | {:error, term()}
  def discover_hosts(opts \\ []) do
    case Keyword.get(opts, :provider) do
      nil ->
        {:error, :missing_provider}

      provider ->
        case Map.fetch(@providers, provider) do
          {:ok, module} -> module.discover_hosts(opts)
          :error -> {:error, {:unknown_provider, provider}}
        end
    end
  end
end

for provider <- [Linode, DigitalOcean, Hetzner, RunPod, VastAi] do
  defmodule Module.concat(Chassis.Inventory.DynamicDiscovery, provider) do
    @moduledoc """
    Phase 3 placeholder for the `#{provider}` provider HTTP client. Returns
    `{:error, {:not_implemented, __MODULE__}}` per
    `0541_implementation_readiness_corrections.md` §1 row 4. Phase 8 wires
    a real HTTP client and `discover_hosts/1` will return `{:ok, [host, ...]}`.
    """
    @behaviour Chassis.Inventory.Discovery

    @impl true
    @spec discover_hosts(keyword()) :: {:error, {:not_implemented, module()}}
    def discover_hosts(_opts \\ []), do: {:error, {:not_implemented, __MODULE__}}
  end
end
