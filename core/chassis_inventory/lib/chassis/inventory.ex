defmodule Chassis.Inventory do
  @moduledoc "Inventory helpers."

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
  @moduledoc "Tenant-filterable physical host."
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
  @moduledoc "Allocated and total resources per host."
  defstruct [:host_ref, total: %{}, allocated: %{}]
  @type t :: %__MODULE__{host_ref: String.t() | nil, total: map(), allocated: map()}
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
  @moduledoc "Placement constraint validation."
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
  @moduledoc "Static host discovery. Uses host_ref as canonical join key."
  @spec discover_hosts(keyword()) :: {:ok, [map()]}
  def discover_hosts(opts \\ []) do
    hosts = Chassis.Inventory.fixture_hosts()

    filtered =
      case Keyword.get(opts, :tenant_ref) do
        nil -> hosts
        tenant_ref -> Enum.filter(hosts, &(tenant_ref in Map.get(&1, :tenant_refs, [])))
      end

    {:ok, filtered}
  end
end

defmodule Chassis.Inventory.DynamicDiscovery do
  @moduledoc "Dynamic discovery facade."
  @spec discover_hosts(keyword()) :: {:ok, [map()]}
  def discover_hosts(opts \\ []), do: Chassis.Inventory.StaticDiscovery.discover_hosts(opts)
end

for provider <- [Linode, DigitalOcean, Hetzner, RunPod, VastAi] do
  defmodule Module.concat(Chassis.Inventory.DynamicDiscovery, provider) do
    @moduledoc "Provider discovery adapter."
    @spec discover_hosts(keyword()) :: {:ok, [map()]}
    def discover_hosts(opts \\ []), do: Chassis.Inventory.StaticDiscovery.discover_hosts(opts)
  end
end
