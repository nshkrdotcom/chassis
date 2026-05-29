defmodule Chassis.Contracts do
  @moduledoc "Pure DTO schemas and behaviours for NSHKR spatial topology."

  @spec round_trip(term()) :: term()
  def round_trip(value), do: value |> :erlang.term_to_binary() |> :erlang.binary_to_term()
end

defmodule Chassis.Contracts.StackTopology do
  @moduledoc "Resolved stack topology."
  @enforce_keys [:topology_ref, :profile_ref, :nodes]
  defstruct [:topology_ref, :profile_ref, :tenant_ref, nodes: [], services: [], metadata: %{}]

  @type t :: %__MODULE__{
          topology_ref: String.t(),
          profile_ref: String.t(),
          tenant_ref: String.t() | nil,
          nodes: [map()],
          services: [map()],
          metadata: map()
        }
end

defmodule Chassis.Contracts.ServiceSpec do
  @moduledoc "Service runtime manifest."
  @enforce_keys [:service_ref, :app_ref, :runtime_profile_ref, :command]
  defstruct [
    :service_ref,
    :app_ref,
    :runtime_profile_ref,
    :command,
    env_files: [],
    args: [],
    ports: []
  ]

  @type t :: %__MODULE__{
          service_ref: String.t(),
          app_ref: String.t(),
          runtime_profile_ref: String.t(),
          command: String.t(),
          env_files: [String.t()],
          args: [String.t()],
          ports: [pos_integer()]
        }
end

defmodule Chassis.Contracts.InstallationManifest do
  @moduledoc "Install paths, deps, OS packages, systemd unit, and release bundle."
  @enforce_keys [:installation_ref, :release_tarball_path]
  defstruct [
    :installation_ref,
    :release_tarball_path,
    :systemd_unit_name,
    paths: %{},
    deps: [],
    os_packages: []
  ]

  @type t :: %__MODULE__{
          installation_ref: String.t(),
          release_tarball_path: String.t(),
          systemd_unit_name: String.t() | nil,
          paths: map(),
          deps: [String.t()],
          os_packages: [String.t()]
        }
end

defmodule Chassis.Contracts.ComponentManifest do
  @moduledoc "Logical virtual-server component signature."
  @enforce_keys [:component_ref, :virtual_server, :service_specs]
  defstruct [:component_ref, :virtual_server, service_specs: [], required_capabilities: %{}]

  @type t :: %__MODULE__{
          component_ref: String.t(),
          virtual_server: atom(),
          service_specs: [Chassis.Contracts.ServiceSpec.t()],
          required_capabilities: map()
        }
end

defmodule Chassis.Contracts.ConfigurationProfile do
  @moduledoc "Maps virtual servers to BEAM nodes for a topology."
  defstruct [:profile_ref, :name, placements: []]

  @type vs_atom ::
          :vs_app_kit
          | :vs_mezzanine
          | :vs_outer_brain
          | :vs_citadel
          | :vs_jido_integration
          | :vs_execution_plane
          | :vs_secrets_plane
          | :vs_observability
  @type placement :: %{
          node_name_pattern: String.t(),
          virtual_servers: [vs_atom()],
          required_resources: map()
        }
  @type t :: %__MODULE__{
          profile_ref: String.t() | nil,
          name: String.t() | nil,
          placements: [placement()]
        }
end

defmodule Chassis.Contracts.PhysicalHost do
  @moduledoc "Physical host descriptor. host_ref is the join key."
  defstruct [
    :host_ref,
    :hostname,
    :ip_address,
    :ssh_port,
    :ssh_user,
    :ssh_key_ref,
    resources: %{},
    region: nil,
    provider: nil,
    status: :unknown,
    tenant_refs: []
  ]

  @type t :: %__MODULE__{
          host_ref: String.t() | nil,
          hostname: String.t() | nil,
          ip_address: String.t() | nil,
          ssh_port: pos_integer() | nil,
          ssh_user: String.t() | nil,
          ssh_key_ref: String.t() | nil,
          resources: map(),
          region: String.t() | nil,
          provider: atom() | String.t() | nil,
          status: atom(),
          tenant_refs: [String.t()]
        }
end

defmodule Chassis.Contracts.BEAMNode do
  @moduledoc "BEAM node placement descriptor."
  defstruct [
    :node_ref,
    :node_name,
    :physical_host_ref,
    :profile_ref,
    virtual_servers: [],
    status: :unknown
  ]

  @type t :: %__MODULE__{
          node_ref: String.t() | nil,
          node_name: atom() | nil,
          physical_host_ref: String.t() | nil,
          profile_ref: String.t() | nil,
          virtual_servers: [atom()],
          status: atom()
        }
end

defmodule Chassis.Contracts.HostProvisioningConfig do
  @moduledoc "OS + provider provisioning configuration."
  defstruct [
    :env_config_ref,
    :os,
    :provider,
    runtime_versions: %{},
    setup_script: [],
    ufw_ports: [],
    install_paths: %{}
  ]

  @type t :: %__MODULE__{
          env_config_ref: String.t() | nil,
          os: String.t() | nil,
          provider: String.t() | nil,
          runtime_versions: map(),
          setup_script: [String.t()],
          ufw_ports: [String.t()],
          install_paths: map()
        }
end

defmodule Chassis.Contracts.EnvironmentResolver do
  @moduledoc "Links ConfigurationProfile + environment to HostProvisioningConfig."
  defstruct [:profile_name, :environment, :provisioning_config_ref]

  @type t :: %__MODULE__{
          profile_name: String.t() | nil,
          environment: :dev | :prod | nil,
          provisioning_config_ref: String.t() | nil
        }
end

defmodule Chassis.Contracts.IsolationProfile do
  @moduledoc "Tenant isolation controls."
  defstruct [
    :isolation_ref,
    compute_isolation: :shared,
    data_isolation: :row,
    secrets_isolation: :shared,
    observability_isolation: :shared_redacted
  ]

  @type t :: %__MODULE__{
          isolation_ref: String.t() | nil,
          compute_isolation: atom(),
          data_isolation: atom(),
          secrets_isolation: atom(),
          observability_isolation: atom()
        }
end

defmodule Chassis.Contracts.ResidencyContract do
  @moduledoc "Allowed regions and providers for a tenant."
  defstruct [:residency_ref, allowed_regions: [], forbidden_regions: [], allowed_providers: []]

  @type t :: %__MODULE__{
          residency_ref: String.t() | nil,
          allowed_regions: [String.t()],
          forbidden_regions: [String.t()],
          allowed_providers: [String.t()]
        }
end

defmodule Chassis.Contracts.Adapter do
  @moduledoc "Behaviour every substrate adapter implements."
  @callback prepare(map(), keyword()) :: {:ok, map()} | {:error, term()}
  @callback start(map(), keyword()) :: {:ok, map()} | {:error, term()}
  @callback stop(map(), keyword()) :: {:ok, map()} | {:error, term()}
  @callback health(map(), keyword()) :: {:ok, map()} | {:error, term()}
end

defmodule NSHKR.Tenant.TenantContext do
  @moduledoc "Tenant context re-exported until nshkr_tenant_contracts is split out."
  @enforce_keys [:tenant_ref, :installation_ref]
  defstruct [
    :tenant_ref,
    :installation_ref,
    :actor_ref,
    :authority_ref,
    :residency_ref,
    :isolation_ref,
    labels: %{}
  ]

  @type t :: %__MODULE__{
          tenant_ref: String.t(),
          installation_ref: String.t(),
          actor_ref: String.t() | nil,
          authority_ref: String.t() | nil,
          residency_ref: String.t() | nil,
          isolation_ref: String.t() | nil,
          labels: map()
        }
end
