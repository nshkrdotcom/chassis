defmodule Chassis.Tenant do
  @moduledoc "Tenant guard facade."
end

defmodule Chassis.Tenant.ResidencyContract do
  @moduledoc "Residency contract."
  defstruct [:residency_ref, allowed_regions: [], forbidden_regions: []]

  @type t :: %__MODULE__{
          residency_ref: String.t() | nil,
          allowed_regions: [String.t()],
          forbidden_regions: [String.t()]
        }
end

defmodule Chassis.Tenant.Residency.Catalog do
  @moduledoc "Residency catalog."
  @spec get(String.t()) :: Chassis.Tenant.ResidencyContract.t()
  def get("residency:us-only"),
    do: %Chassis.Tenant.ResidencyContract{
      residency_ref: "residency:us-only",
      allowed_regions: ["us-west", "us-east", "local"]
    }

  def get(ref),
    do: %Chassis.Tenant.ResidencyContract{residency_ref: ref, allowed_regions: ["local"]}
end

defmodule Chassis.Tenant.IsolationProfile do
  @moduledoc "Isolation profile."
  defstruct [
    :isolation_ref,
    compute_isolation: :shared,
    observability_isolation: :shared_redacted
  ]

  @type t :: %__MODULE__{
          isolation_ref: String.t() | nil,
          compute_isolation: atom(),
          observability_isolation: atom()
        }
end

defmodule Chassis.Tenant.Isolation.Catalog do
  @moduledoc "Isolation catalog."
  @spec get(String.t()) :: Chassis.Tenant.IsolationProfile.t()
  def get("isolation:dedicated-node"),
    do: %Chassis.Tenant.IsolationProfile{
      isolation_ref: "isolation:dedicated-node",
      compute_isolation: :dedicated_node
    }

  def get(ref), do: %Chassis.Tenant.IsolationProfile{isolation_ref: ref}
end

defmodule Chassis.Tenant.ResourceQuota do
  @moduledoc "Resource quota."
  defstruct [:quota_ref, cpu_cores: 0, gpu_count: 0, ram_gb: 0]

  @type t :: %__MODULE__{
          quota_ref: String.t() | nil,
          cpu_cores: non_neg_integer(),
          gpu_count: non_neg_integer(),
          ram_gb: non_neg_integer()
        }
end

defmodule Chassis.Tenant.Quota.Catalog do
  @moduledoc "Quota catalog."
  @spec get(String.t()) :: Chassis.Tenant.ResourceQuota.t()
  def get(ref),
    do: %Chassis.Tenant.ResourceQuota{quota_ref: ref, cpu_cores: 64, gpu_count: 8, ram_gb: 512}
end

defmodule Chassis.Tenant.TopologyGuard do
  @moduledoc "Residency and isolation topology guard."
  @spec validate(map(), map()) :: :ok | {:error, atom()}
  def validate(topology, %{residency_ref: residency_ref}) do
    residency = Chassis.Tenant.Residency.Catalog.get(residency_ref || "residency:local")
    regions = topology |> Map.get(:hosts, []) |> Enum.map(&Map.get(&1, :region, "local"))

    if Enum.all?(regions, &(&1 in residency.allowed_regions)),
      do: :ok,
      else: {:error, :residency_violation}
  end
end

defmodule Chassis.Tenant.QuotaGuard do
  @moduledoc "Quota admission guard."
  @spec check(map(), Chassis.Tenant.ResourceQuota.t()) :: :ok | {:error, atom()}
  def check(request, quota) do
    cond do
      Map.get(request, :cpu_cores, 0) > quota.cpu_cores -> {:error, :cpu_quota_exceeded}
      Map.get(request, :gpus, 0) > quota.gpu_count -> {:error, :gpu_quota_exceeded}
      Map.get(request, :ram_gb, 0) > quota.ram_gb -> {:error, :memory_quota_exceeded}
      true -> :ok
    end
  end
end

defmodule Chassis.Tenant.GuardSupervisor do
  @moduledoc "Tenant guard supervisor placeholder."
  use GenServer

  def start_link(opts \\ []),
    do: GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))

  @impl true
  def init(opts), do: {:ok, opts}
end

defmodule Chassis.Tenant.QuotaConsumptionTracker do
  @moduledoc "Quota consumption tracker."
  @spec current(String.t()) :: map()
  def current(tenant_ref), do: %{tenant_ref: tenant_ref, cpu_cores: 0, gpus: 0, ram_gb: 0}
end
