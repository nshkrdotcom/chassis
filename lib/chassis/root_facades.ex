defmodule Chassis.Contracts.ConfigurationProfile do
  @moduledoc "Workspace-root smoke facade for the contracts package struct."
  defstruct [:profile_ref, :name, placements: []]
end

defmodule Chassis.Receipts.Store.Memory do
  @moduledoc "Workspace-root smoke facade for receipt storage."

  @spec put_smoke() :: {:ok, map()}
  def put_smoke,
    do: {:ok, %{receipt_ref: "receipt:smoke", kind: :smoke, secret_ref: "[REDACTED]"}}
end

defmodule Chassis.Inventory.StaticDiscovery do
  @moduledoc "Workspace-root smoke facade for static discovery."

  @spec discover_hosts(keyword()) :: {:ok, [map()]}
  def discover_hosts(_opts \\ []) do
    {:ok,
     [
       %{host_ref: "host:local", region: "local", resources: %{cpu_cores: 8, gpus: 0}},
       %{host_ref: "host:gpu-fixture", region: "us-west", resources: %{cpu_cores: 16, gpus: 1}}
     ]}
  end
end

defmodule Chassis.Core.Engine do
  @moduledoc "Workspace-root smoke facade for the core engine."
  use GenServer

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts), do: {:ok, :offline}

  @spec state() :: atom()
  def state, do: GenServer.call(__MODULE__, :state)

  @impl true
  def handle_call(:state, _from, state), do: {:reply, state, state}
end

defmodule Chassis.Stack.ProfileResolver do
  @moduledoc "Workspace-root smoke facade for profile resolution."

  @spec resolve(String.t(), :dev | :prod) :: {:ok, map()}
  def resolve(profile_ref, env) do
    {:ok,
     %{
       profile_ref: profile_ref,
       env: env,
       adapters:
         if(env == :dev,
           do: %{
             discovery: :static,
             provisioning: :local_noop,
             secrets: :env,
             mesh: :local_loopback
           },
           else: %{
             discovery: :dynamic,
             provisioning: :ssh_bootstrap,
             secrets: :sops,
             mesh: :beam_tls
           }
         )
     }}
  end
end

defmodule Chassis.Environments.FileBasedEnvironments do
  @moduledoc "Workspace-root smoke facade for embedded environments."

  @spec list_environments() :: {:ok, [map()]}
  def list_environments do
    {:ok,
     Enum.map(
       ~w(linode_ubuntu_24_04 digital_ocean_ubuntu_24_04 hetzner_ubuntu_24_04 local_ubuntu_24_04),
       fn ref ->
         %{env_config_ref: ref, os: "ubuntu_24_04"}
       end
     )}
  end

  @spec resolve(String.t(), :dev | :prod) :: {:ok, map()}
  def resolve(_profile_ref, :dev), do: {:ok, %{env_config_ref: "local_ubuntu_24_04"}}

  def resolve("profile:ternary-split-3", :prod),
    do: {:ok, %{env_config_ref: "linode_ubuntu_24_04"}}

  def resolve(_profile_ref, :prod), do: {:ok, %{env_config_ref: "linode_ubuntu_24_04"}}
end

defmodule Chassis.Evolution.States do
  @moduledoc "Workspace-root smoke facade for evolution states."
  @states [
    :queued,
    :evidence_curated,
    :planning,
    :patching,
    :building,
    :trial_provisioning,
    :trial_running,
    :scoring,
    :blocked,
    :converged,
    :awaiting_authority,
    :awaiting_operator_consent,
    :promotion_requested,
    :promoting,
    :committed,
    :rolled_back,
    :failed,
    :stopped
  ]

  @spec all() :: [atom()]
  def all, do: @states

  @spec terminal?(atom()) :: boolean()
  def terminal?(state), do: state in [:committed, :rolled_back, :failed, :stopped]
end

defmodule Chassis.FailureBatches do
  @moduledoc "Workspace-root smoke facade for failure batches."

  @spec fixture() :: map()
  def fixture,
    do: %{
      tenant_ref: "tenant:dev",
      installation_ref: "installation:dev",
      evidence_refs: ["ev:smoke:1"]
    }

  @spec create_batch(map()) :: {:ok, map()}
  def create_batch(attrs) do
    {:ok, Map.merge(%{failure_batch_ref: "fb:dev:smoke", redaction_posture: :default}, attrs)}
  end
end

defmodule Chassis.Candidate.Registry do
  @moduledoc "Workspace-root smoke facade for candidate registry."

  @spec list(keyword()) :: [map()]
  def list(_opts \\ []), do: []
end
