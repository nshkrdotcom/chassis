defmodule Chassis.Fixtures do
  @moduledoc "Canonical topology fixtures."

  @profiles [
    {"profile:monolith", 1},
    {"profile:decoupled-cockpit-2", 2},
    {"profile:ternary-split-3", 3},
    {"profile:maximal-decoupled", 8}
  ]
  @apps [:extravaganza, :stack_coder]
  @envs [:dev, :prod]

  @spec hosts() :: [map()]
  def hosts do
    [
      host("host:local-monolith", "monolith@local", "us-west", 32, 128),
      host("host:appkit", "appkit@local", "us-west", 8, 32),
      host("host:stack", "stack@local", "us-east", 16, 64),
      host("host:control", "control@local", "us-east", 8, 32),
      host("host:data", "data@local", "us-west", 16, 64)
    ] ++
      Enum.map(
        [
          :vs_app_kit,
          :vs_mezzanine,
          :vs_outer_brain,
          :vs_citadel,
          :vs_jido_integration,
          :vs_execution_plane,
          :vs_secrets_plane,
          :vs_observability
        ],
        fn vs ->
          name = Atom.to_string(vs)
          host("host:#{name}", "#{name}@local", "us-west", 4, 16)
        end
      )
  end

  @spec deployment_fixtures() :: [map()]
  def deployment_fixtures do
    for {profile_ref, expected_node_count} <- @profiles,
        app_atom <- @apps,
        env <- @envs do
      %{
        fixture_ref: "fixture:chassis:#{app_atom}:#{profile_ref}:#{env}",
        app_atom: app_atom,
        profile_ref: profile_ref,
        env: env,
        expected_node_count: expected_node_count,
        tenant_ref: "tenant:dev",
        installation_ref: "installation:dev",
        residency_ref: "residency:global",
        isolation_profile_ref: "isolation:dev-shared",
        quota_ref: "quota:tenant:enterprise",
        hosts: hosts()
      }
    end
  end

  @spec fixture!(String.t(), atom(), :dev | :prod) :: map()
  def fixture!(profile_ref, app_atom, env) do
    Enum.find(deployment_fixtures(), fn fixture ->
      fixture.profile_ref == profile_ref and fixture.app_atom == app_atom and fixture.env == env
    end) || raise ArgumentError, "unknown fixture #{inspect({profile_ref, app_atom, env})}"
  end

  @spec residency_violation_fixture() :: map()
  def residency_violation_fixture do
    %{
      fixture_ref: "fixture:chassis:residency:violation",
      app_atom: :extravaganza,
      profile_ref: "profile:monolith",
      env: :dev,
      expected_node_count: 1,
      tenant_ref: "tenant:dev",
      installation_ref: "installation:dev",
      residency_ref: "residency:us-only",
      isolation_profile_ref: "isolation:dev-shared",
      quota_ref: "quota:tenant:enterprise",
      hosts: [host("host:eu", "monolith@eu", "eu-central", 32, 128)]
    }
  end

  @spec topology(String.t(), :dev | :prod) :: {:ok, map()} | {:error, term()}
  def topology(profile_ref \\ "profile:monolith", env \\ :dev) do
    Chassis.Stack.Composer.compose(profile_ref, env, hosts())
  end

  @spec run_deployment(map()) :: {:ok, map()} | {:error, term()}
  def run_deployment(fixture) when is_map(fixture) do
    with {:ok, runtime} <- start_runtime() do
      fixture
      |> transaction_attrs(runtime)
      |> Chassis.StackManager.Transaction.run()
    end
  end

  @spec start_runtime() :: {:ok, map()} | {:error, term()}
  def start_runtime do
    with {:ok, registry} <- Chassis.AppRegistry.start_link(name: nil),
         {:ok, receipts_store} <- Chassis.Receipts.Store.Memory.start_link(name: nil),
         {:ok, fence_store} <- Chassis.StackManager.FenceStore.start_link(name: nil),
         {:ok, checkpoint_store} <- Chassis.StackManager.CheckpointStore.start_link(name: nil) do
      {:ok,
       %{
         registry: registry,
         receipts_store: receipts_store,
         fence_store: fence_store,
         checkpoint_store: checkpoint_store
       }}
    end
  end

  @spec transaction_attrs(map(), map(), map()) :: map()
  def transaction_attrs(fixture, runtime, overrides \\ %{}) do
    %{
      app_atom: fixture.app_atom,
      profile_ref: fixture.profile_ref,
      env: fixture.env,
      tenant_ref: fixture.tenant_ref,
      installation_ref: fixture.installation_ref,
      residency_ref: fixture.residency_ref,
      isolation_profile_ref: fixture.isolation_profile_ref,
      quota_ref: fixture.quota_ref,
      hosts: fixture.hosts,
      registry: runtime.registry,
      receipts_store: runtime.receipts_store,
      fence_store: runtime.fence_store,
      checkpoint_store: runtime.checkpoint_store,
      authority_ref: "authority:stacklab:phase21",
      idempotency_key: fixture.fixture_ref,
      git_sha: "phase21-fixture",
      release_version: "phase21",
      provision: fn _topology -> {:ok, :local_noop} end,
      mesh_join: &mesh_nodes/1
    }
    |> Map.merge(overrides)
  end

  @spec mesh_nodes(map()) :: {:ok, [node()]}
  def mesh_nodes(%{assignments: assignments}) when is_list(assignments) do
    nodes =
      assignments
      |> Enum.map(&Map.fetch!(&1, :node_name_pattern))
      |> Enum.map(fn pattern ->
        pattern
        |> String.replace("@*", "@local")
        |> String.to_atom()
      end)

    {:ok, nodes}
  end

  defp host(host_ref, hostname, region, cpu_cores, ram_gb) do
    %{
      host_ref: host_ref,
      provider: :local,
      region: region,
      hostname: hostname,
      resources: %{cpu_cores: cpu_cores, ram_gb: ram_gb, gpus: 0, disk_gb: 1024},
      tenant_refs: ["tenant:dev"]
    }
  end
end
