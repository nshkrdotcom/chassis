defmodule Chassis.Tenant do
  @moduledoc "Tenant isolation, residency, and quota guard facade."
end

defmodule Chassis.Tenant.TenantContext do
  @moduledoc "Tenant context required by mutating deployment paths."

  @enforce_keys [:tenant_ref, :installation_ref, :authority_ref, :trace_id]
  defstruct [
    :tenant_ref,
    :installation_ref,
    :actor_ref,
    :system_actor_ref,
    :authority_ref,
    :budget_ref,
    :residency_ref,
    :isolation_profile_ref,
    :trace_id
  ]
end

defmodule Chassis.Tenant.ResidencyContract do
  @moduledoc "Tenant residency contract."

  defstruct [
    :residency_ref,
    :tenant_ref,
    allowed_regions: [],
    allowed_providers: [],
    forbidden_regions: [],
    forbidden_providers: [],
    default_failure_posture: :fail_closed
  ]

  @type t :: %__MODULE__{
          residency_ref: String.t() | nil,
          tenant_ref: String.t() | nil,
          allowed_regions: [String.t()],
          allowed_providers: [atom()],
          forbidden_regions: [String.t()],
          forbidden_providers: [atom()],
          default_failure_posture: :fail_closed | :warn
        }
end

defmodule Chassis.Tenant.Residency.Catalog do
  @moduledoc "Compile-time residency catalog."

  alias Chassis.Tenant.ResidencyContract

  @contracts %{
    "residency:us-only" => %ResidencyContract{
      residency_ref: "residency:us-only",
      allowed_regions: ["us-east-1", "us-west-1", "us-central-1", "newark", "atlanta", "dallas"],
      allowed_providers: [:linode, :digital_ocean, :hetzner, :local],
      forbidden_regions: [],
      forbidden_providers: [],
      default_failure_posture: :fail_closed
    },
    "residency:eu-only" => %ResidencyContract{
      residency_ref: "residency:eu-only",
      allowed_regions: ["fra1", "fra-de", "fsn1", "ams3", "lhr1"],
      allowed_providers: [:hetzner, :digital_ocean],
      forbidden_regions: [],
      forbidden_providers: [],
      default_failure_posture: :fail_closed
    },
    "residency:global" => %ResidencyContract{
      residency_ref: "residency:global",
      allowed_regions: ["*"],
      allowed_providers: [:linode, :digital_ocean, :hetzner, :local, :fixture],
      forbidden_regions: [],
      forbidden_providers: [],
      default_failure_posture: :warn
    }
  }

  @spec fetch(String.t()) :: {:ok, ResidencyContract.t()} | {:error, :unknown_residency}
  def fetch(ref) when is_binary(ref) do
    case Map.fetch(@contracts, ref) do
      {:ok, contract} -> {:ok, contract}
      :error -> {:error, :unknown_residency}
    end
  end

  @spec get(String.t()) :: ResidencyContract.t()
  def get(ref) do
    case fetch(ref) do
      {:ok, contract} -> contract
      {:error, :unknown_residency} -> %ResidencyContract{residency_ref: ref}
    end
  end
end

defmodule Chassis.Tenant.IsolationProfile do
  @moduledoc "Tenant isolation profile."

  defstruct [
    :isolation_profile_ref,
    :data_isolation,
    :compute_isolation,
    :memory_isolation,
    :secret_isolation,
    :artifact_isolation,
    :network_isolation,
    :observability_isolation,
    :audit_isolation,
    default_failure_posture: :fail_closed
  ]

  @type t :: %__MODULE__{
          isolation_profile_ref: String.t() | nil,
          data_isolation: atom() | nil,
          compute_isolation: atom() | nil,
          memory_isolation: atom() | nil,
          secret_isolation: atom() | nil,
          artifact_isolation: atom() | nil,
          network_isolation: atom() | nil,
          observability_isolation: atom() | nil,
          audit_isolation: atom() | nil,
          default_failure_posture: :fail_closed | :warn
        }
end

defmodule Chassis.Tenant.Isolation.Catalog do
  @moduledoc "Compile-time tenant isolation catalog."

  alias Chassis.Tenant.IsolationProfile

  @profiles %{
    "isolation:dev-shared" => %IsolationProfile{
      isolation_profile_ref: "isolation:dev-shared",
      data_isolation: :row_level,
      compute_isolation: :shared_pool,
      memory_isolation: :tenant_scoped,
      secret_isolation: :tenant_scoped,
      artifact_isolation: :shared_verified,
      network_isolation: :shared_egress,
      observability_isolation: :shared_redacted,
      audit_isolation: :tenant_partitioned,
      default_failure_posture: :warn
    },
    "isolation:shared-standard" => %IsolationProfile{
      isolation_profile_ref: "isolation:shared-standard",
      data_isolation: :schema,
      compute_isolation: :shared_pool,
      memory_isolation: :tenant_scoped,
      secret_isolation: :tenant_scoped,
      artifact_isolation: :tenant_private,
      network_isolation: :tenant_egress_profile,
      observability_isolation: :tenant_partitioned,
      audit_isolation: :tenant_partitioned,
      default_failure_posture: :fail_closed
    },
    "isolation:dedicated-gpu" => %IsolationProfile{
      isolation_profile_ref: "isolation:dedicated-gpu",
      data_isolation: :database,
      compute_isolation: :dedicated_node,
      memory_isolation: :installation_scoped,
      secret_isolation: :installation_scoped,
      artifact_isolation: :dedicated_store,
      network_isolation: :denied_by_default,
      observability_isolation: :tenant_partitioned,
      audit_isolation: :tenant_partitioned,
      default_failure_posture: :fail_closed
    }
  }

  @spec fetch(String.t()) :: {:ok, IsolationProfile.t()} | {:error, :unknown_isolation_profile}
  def fetch(ref) when is_binary(ref) do
    case Map.fetch(@profiles, ref) do
      {:ok, profile} -> {:ok, profile}
      :error -> {:error, :unknown_isolation_profile}
    end
  end

  @spec get(String.t()) :: IsolationProfile.t()
  def get(ref) do
    case fetch(ref) do
      {:ok, profile} -> profile
      {:error, :unknown_isolation_profile} -> %IsolationProfile{isolation_profile_ref: ref}
    end
  end
end

defmodule Chassis.Tenant.ResourceQuota do
  @moduledoc "Tenant resource quota."

  defstruct [:quota_ref, :tenant_ref, limits: %{}, burst: %{}, enforcement: :admit_or_deny]

  @type t :: %__MODULE__{
          quota_ref: String.t() | nil,
          tenant_ref: String.t() | nil,
          limits: map(),
          burst: map(),
          enforcement: :admit_or_deny | :admit_with_warning
        }
end

defmodule Chassis.Tenant.Quota.Catalog do
  @moduledoc "Compile-time quota catalog."

  alias Chassis.Tenant.ResourceQuota

  @quotas %{
    "quota:tenant:dev" => %ResourceQuota{
      quota_ref: "quota:tenant:dev",
      limits: %{cpu_total: 4, ram_gb_total: 8, gpu_total: 0}
    },
    "quota:tenant:starter" => %ResourceQuota{
      quota_ref: "quota:tenant:starter",
      limits: %{cpu_total: 8, ram_gb_total: 16, gpu_total: 0}
    },
    "quota:tenant:scale" => %ResourceQuota{
      quota_ref: "quota:tenant:scale",
      limits: %{cpu_total: 32, ram_gb_total: 128, gpu_total: 2}
    },
    "quota:tenant:enterprise" => %ResourceQuota{
      quota_ref: "quota:tenant:enterprise",
      limits: %{cpu_total: 256, ram_gb_total: 1024, gpu_total: 16}
    }
  }

  @spec fetch(String.t()) :: {:ok, ResourceQuota.t()} | {:error, :unknown_quota}
  def fetch(ref) when is_binary(ref) do
    case Map.fetch(@quotas, ref) do
      {:ok, quota} -> {:ok, quota}
      :error -> {:error, :unknown_quota}
    end
  end

  @spec get(String.t()) :: ResourceQuota.t()
  def get(ref) do
    case fetch(ref) do
      {:ok, quota} -> quota
      {:error, :unknown_quota} -> %ResourceQuota{quota_ref: ref}
    end
  end
end

defmodule Chassis.Tenant.TopologyGuard do
  @moduledoc "Validates topology against tenant context, isolation, residency, quota, and capacity."

  alias Chassis.Tenant.{IsolationProfile, ResidencyContract, ResourceQuota}

  @spec validate(map(), keyword()) :: {:ok, map()} | {:error, term()}
  def validate(input, opts \\ []) when is_map(input) and is_list(opts) do
    errors =
      []
      |> validate_required_context(input)
      |> validate_isolation(input)
      |> validate_residency(input)
      |> validate_quota(input)
      |> validate_capacity(input)
      |> validate_provider_eligibility(input)
      |> Enum.reverse()

    {:ok,
     %{
       valid?: errors == [],
       errors: errors,
       warnings: [],
       observability: observability(input)
     }}
  end

  defp validate_required_context(errors, input) do
    [:tenant_ref, :installation_ref]
    |> Enum.reduce(errors, fn field, acc ->
      case Map.get(input, field) do
        value when is_binary(value) and value != "" -> acc
        _ -> [error(:tenant_context_required, "#{field} is required") | acc]
      end
    end)
  end

  defp validate_isolation(
         errors,
         %{isolation_profile: %IsolationProfile{compute_isolation: :dedicated_node}} = input
       ) do
    tenant_ref = Map.get(input, :tenant_ref)

    if Enum.any?(Map.get(input, :hosts, []), &shared_with_other_tenant?(&1, tenant_ref)) do
      [
        error(
          :isolation_violation,
          "Tenant requires dedicated_node compute isolation; host is already assigned to another tenant"
        )
        | errors
      ]
    else
      errors
    end
  end

  defp validate_isolation(errors, _input), do: errors

  defp validate_residency(errors, %{residency_contract: %ResidencyContract{} = contract} = input) do
    Enum.reduce(Map.get(input, :hosts, []), errors, fn host, acc ->
      region = host_value(host, :region)

      cond do
        is_nil(region) ->
          acc

        region in contract.forbidden_regions ->
          [residency_error(host, region) | acc]

        contract.allowed_regions == ["*"] or region in contract.allowed_regions ->
          acc

        true ->
          [residency_error(host, region) | acc]
      end
    end)
  end

  defp validate_residency(errors, _input), do: errors

  defp validate_quota(errors, %{resource_quota: %ResourceQuota{} = quota, profile: profile}) do
    required = required_resources(profile)
    limits = quota.limits || %{}

    errors
    |> maybe_quota_error(:cpu_total, :cpu_cores, required, limits, "CPU quota exceeded")
    |> maybe_quota_error(:ram_gb_total, :ram_gb, required, limits, "RAM quota exceeded")
    |> maybe_quota_error(:gpu_total, :gpus, required, limits, "GPU quota exceeded")
  end

  defp validate_quota(errors, _input), do: errors

  defp validate_capacity(errors, input) do
    hosts = Map.get(input, :hosts, [])

    input
    |> placements()
    |> Enum.reduce(errors, fn placement, acc ->
      required = Map.get(placement, :required_resources, %{})
      candidates = matching_hosts(hosts, Map.get(placement, :node_name_pattern))

      if Enum.any?(candidates, &host_fits?(&1, required)) do
        acc
      else
        [
          error(
            :insufficient_capacity,
            "No host has capacity for #{Map.get(placement, :node_name_pattern)}"
          )
          | acc
        ]
      end
    end)
  end

  defp validate_provider_eligibility(
         errors,
         %{residency_contract: %ResidencyContract{} = contract} = input
       ) do
    Enum.reduce(Map.get(input, :hosts, []), errors, fn host, acc ->
      provider = host_value(host, :provider)

      cond do
        is_nil(provider) ->
          acc

        provider in contract.forbidden_providers ->
          [provider_error(host, provider) | acc]

        contract.allowed_providers == [] or provider in contract.allowed_providers ->
          acc

        true ->
          [provider_error(host, provider) | acc]
      end
    end)
  end

  defp validate_provider_eligibility(errors, _input), do: errors

  @spec required_resources(map()) :: map()
  def required_resources(profile) when is_map(profile) do
    profile
    |> placements()
    |> Enum.reduce(%{cpu_cores: 0, ram_gb: 0, gpus: 0}, fn placement, acc ->
      resources = Map.get(placement, :required_resources, %{})

      %{
        cpu_cores: acc.cpu_cores + Map.get(resources, :cpu_cores, 0),
        ram_gb: acc.ram_gb + Map.get(resources, :ram_gb, 0),
        gpus: acc.gpus + Map.get(resources, :gpus, 0)
      }
    end)
  end

  defp placements(%{profile: profile}), do: placements(profile)
  defp placements(%{placements: placements}) when is_list(placements), do: placements
  defp placements(_profile), do: []

  defp matching_hosts(hosts, pattern) do
    matched = Enum.filter(hosts, &node_matches?(&1, pattern))
    if matched == [], do: hosts, else: matched
  end

  defp node_matches?(_host, nil), do: true

  defp node_matches?(host, pattern) do
    hostname =
      host_value(host, :hostname) || host_value(host, :node_name) || host_value(host, :host_ref)

    prefix = String.replace_suffix(pattern, "@*", "@")
    is_binary(hostname) and (String.starts_with?(hostname, prefix) or pattern == "monolith@*")
  end

  defp host_fits?(host, required) do
    resources = host_value(host, :resources) || %{}

    Map.get(resources, :cpu_cores, 0) >= Map.get(required, :cpu_cores, 0) and
      Map.get(resources, :ram_gb, 0) >= Map.get(required, :ram_gb, 0) and
      Map.get(resources, :gpus, 0) >= Map.get(required, :gpus, 0)
  end

  defp shared_with_other_tenant?(host, tenant_ref) do
    host
    |> host_value(:tenant_refs)
    |> List.wrap()
    |> Enum.any?(&(&1 != tenant_ref))
  end

  defp maybe_quota_error(errors, limit_key, resource_key, required, limits, message) do
    limit = Map.get(limits, limit_key, :infinity)

    if limit != :infinity and Map.get(required, resource_key, 0) > limit do
      [error(:quota_exceeded, message) | errors]
    else
      errors
    end
  end

  defp residency_error(host, region) do
    error(
      :residency_violation,
      "Host #{host_value(host, :host_ref)} is in disallowed region #{region}",
      placement_ref: host_value(host, :host_ref),
      region: region
    )
  end

  defp provider_error(host, provider) do
    error(:provider_not_allowed, "Provider #{provider} is not tenant-allowed",
      placement_ref: host_value(host, :host_ref),
      provider: provider
    )
  end

  defp observability(%{tenant_ref: tenant_ref, isolation_profile: %IsolationProfile{} = profile})
       when is_binary(tenant_ref) do
    %{tenant_label: Chassis.Tenant.Observability.tenant_label(tenant_ref, profile)}
  end

  defp observability(_input), do: %{}

  defp host_value(host, key) when is_map(host),
    do: Map.get(host, key, Map.get(host, Atom.to_string(key)))

  defp error(code, message, extra \\ []) do
    extra
    |> Map.new()
    |> Map.merge(%{code: code, safe_message: message})
  end
end

defmodule Chassis.Tenant.QuotaGuard do
  @moduledoc "Quota admission guard."

  alias Chassis.Tenant.{QuotaConsumptionTracker, ResourceQuota}

  @spec check(ResourceQuota.t(), map()) :: {:ok, map()}
  def check(%ResourceQuota{} = quota, requested) when is_map(requested) do
    current = QuotaConsumptionTracker.fetch(quota.tenant_ref)
    limits = quota.limits || %{}

    cond do
      usage(requested, current, :cpu_cores) > Map.get(limits, :cpu_total, :infinity) ->
        {:ok, deny(:cpu_quota_exceeded, "Tenant CPU quota exceeded")}

      usage(requested, current, :gpus) > Map.get(limits, :gpu_total, :infinity) ->
        {:ok, deny(:gpu_quota_exceeded, "Tenant GPU quota exceeded")}

      usage(requested, current, :ram_gb) > Map.get(limits, :ram_gb_total, :infinity) ->
        {:ok, deny(:memory_quota_exceeded, "Tenant RAM quota exceeded")}

      true ->
        {:ok, %{allowed?: true, reason: nil, retry_after: nil, safe_message: nil}}
    end
  end

  defp usage(requested, current, key), do: Map.get(requested, key, 0) + Map.get(current, key, 0)

  defp deny(reason, message),
    do: %{allowed?: false, reason: reason, retry_after: nil, safe_message: message}
end

defmodule Chassis.Tenant.GuardSupervisor do
  @moduledoc "Tenant guard supervisor."
  use Supervisor

  def start_link(opts \\ []),
    do: Supervisor.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))

  @impl true
  def init(_opts) do
    Supervisor.init([Chassis.Tenant.QuotaConsumptionTracker], strategy: :one_for_one)
  end
end

defmodule Chassis.Tenant.QuotaConsumptionTracker do
  @moduledoc "In-memory quota consumption tracker."
  use GenServer

  @zero %{cpu_cores: 0, gpus: 0, ram_gb: 0}

  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)

    if name do
      GenServer.start_link(__MODULE__, opts, name: name)
    else
      GenServer.start_link(__MODULE__, opts)
    end
  end

  @spec fetch(String.t() | nil, GenServer.server()) :: map()
  def fetch(tenant_ref, server \\ __MODULE__)

  def fetch(nil, _server), do: @zero

  def fetch(tenant_ref, server) do
    case resolve_server(server) do
      nil -> Map.put(@zero, :tenant_ref, tenant_ref)
      resolved -> GenServer.call(resolved, {:fetch, tenant_ref})
    end
  end

  @spec put(String.t(), map()) :: :ok
  def put(tenant_ref, usage), do: put(__MODULE__, tenant_ref, usage)

  @spec put(GenServer.server(), String.t(), map()) :: :ok
  def put(server, tenant_ref, usage) when is_binary(tenant_ref) and is_map(usage) do
    GenServer.call(server, {:put, tenant_ref, Map.merge(@zero, usage)})
  end

  @impl true
  def init(_opts), do: {:ok, %{}}

  @impl true
  def handle_call({:fetch, tenant_ref}, _from, state) do
    {:reply, Map.get(state, tenant_ref, Map.put(@zero, :tenant_ref, tenant_ref)), state}
  end

  def handle_call({:put, tenant_ref, usage}, _from, state) do
    {:reply, :ok, Map.put(state, tenant_ref, usage)}
  end

  defp resolve_server(pid) when is_pid(pid), do: pid
  defp resolve_server(name) when is_atom(name), do: Process.whereis(name)
  defp resolve_server(other), do: other
end

defmodule Chassis.Tenant.Observability do
  @moduledoc "Tenant label partitioning helpers."

  alias Chassis.Tenant.IsolationProfile

  @spec tenant_label(String.t(), IsolationProfile.t()) :: String.t()
  def tenant_label(tenant_ref, %IsolationProfile{observability_isolation: :shared_redacted}) do
    digest =
      :crypto.hash(:sha256, tenant_ref)
      |> Base.encode16(case: :lower)
      |> binary_part(0, 16)

    "tenant_hash:" <> digest
  end

  def tenant_label(tenant_ref, %IsolationProfile{observability_isolation: :tenant_partitioned}),
    do: tenant_ref

  def tenant_label(tenant_ref, %IsolationProfile{}),
    do: tenant_label(tenant_ref, %IsolationProfile{observability_isolation: :shared_redacted})
end
