defmodule Chassis.Stack do
  @moduledoc """
  Profile and placement facade. Composes:

  * `Chassis.Stack.ConfigurationProfile` — compile-time registry of the four
    canonical profiles from `0505_virtual_physical_mapping_architecture.md` §3.
  * `Chassis.Stack.ProfileResolver` — `(profile_ref, env) -> resolved map`
    with the dev/prod adapter set.
  * `Chassis.Stack.PlacementPlanner` — assigns placements to hosts subject to
    `Chassis.Inventory.PlacementValidator` capacity checks. No round-robin
    over capacity constraints.
  * `Chassis.Stack.Composer` — end-to-end: profile + env + hosts -> topology.

  No `case node() do :appkit@_ -> ...` patterns: node-name matching uses the
  pattern strings `"<vs>@*"` registered in the placement records.
  """
end

defmodule Chassis.Stack.ConfigurationProfile do
  @moduledoc "Compile-time profile registry per 0505 §3."

  @profiles %{
    "profile:monolith" => [
      %{
        node_name_pattern: "monolith@*",
        virtual_servers: [
          :vs_app_kit,
          :vs_mezzanine,
          :vs_outer_brain,
          :vs_citadel,
          :vs_jido_integration,
          :vs_execution_plane,
          :vs_secrets_plane,
          :vs_observability
        ],
        required_resources: %{cpu_cores: 4, ram_gb: 8, gpus: 0}
      }
    ],
    "profile:decoupled-cockpit-2" => [
      %{
        node_name_pattern: "appkit@*",
        virtual_servers: [:vs_app_kit, :vs_observability],
        required_resources: %{cpu_cores: 2, ram_gb: 4, gpus: 0}
      },
      %{
        node_name_pattern: "stack@*",
        virtual_servers: [
          :vs_mezzanine,
          :vs_outer_brain,
          :vs_citadel,
          :vs_jido_integration,
          :vs_execution_plane,
          :vs_secrets_plane
        ],
        required_resources: %{cpu_cores: 4, ram_gb: 16, gpus: 0}
      }
    ],
    "profile:ternary-split-3" => [
      %{
        node_name_pattern: "appkit@*",
        virtual_servers: [:vs_app_kit, :vs_observability],
        required_resources: %{cpu_cores: 2, ram_gb: 4, gpus: 0}
      },
      %{
        node_name_pattern: "control@*",
        virtual_servers: [:vs_mezzanine, :vs_citadel, :vs_secrets_plane],
        required_resources: %{cpu_cores: 4, ram_gb: 16, gpus: 0}
      },
      %{
        node_name_pattern: "data@*",
        virtual_servers: [:vs_outer_brain, :vs_jido_integration, :vs_execution_plane],
        required_resources: %{cpu_cores: 8, ram_gb: 32, gpus: 0}
      }
    ],
    "profile:maximal-decoupled" =>
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
          %{
            node_name_pattern: Atom.to_string(vs) <> "@*",
            virtual_servers: [vs],
            required_resources: %{cpu_cores: 2, ram_gb: 4, gpus: 0}
          }
        end
      )
  }

  @spec all() :: %{optional(String.t()) => [map()]}
  def all, do: @profiles

  @spec get(String.t()) :: {:ok, map()} | {:error, :unknown_profile}
  def get(ref) do
    case Map.fetch(@profiles, ref) do
      {:ok, placements} -> {:ok, %{profile_ref: ref, placements: placements}}
      :error -> {:error, :unknown_profile}
    end
  end
end

defmodule Chassis.Stack.ProfileResolver do
  @moduledoc """
  Resolves a `(profile_ref, env)` pair into the `resolved()` map documented
  in `0505_virtual_physical_mapping_architecture.md` §4.

  The dev adapter set is fully local-loopback; the prod adapter set is
  SSH + SOPS + BEAM-TLS.
  """

  @dev_adapters %{
    discovery: :static,
    provisioning: :local_noop,
    secrets: :env,
    mesh: :local_loopback
  }

  @prod_adapters %{
    discovery: :dynamic,
    provisioning: :ssh_bootstrap,
    secrets: :sops,
    mesh: :beam_tls
  }

  @spec resolve(String.t(), :dev | :prod) :: {:ok, map()} | {:error, term()}
  def resolve(profile_ref, env) when env in [:dev, :prod] do
    with {:ok, profile} <- Chassis.Stack.ConfigurationProfile.get(profile_ref) do
      adapters = if env == :dev, do: @dev_adapters, else: @prod_adapters
      {:ok, Map.merge(profile, %{env: env, adapters: adapters})}
    end
  end

  def resolve(_profile_ref, env), do: {:error, {:unknown_environment, env}}
end

defmodule Chassis.Stack.PlacementPlanner do
  @moduledoc """
  Assigns each placement to a host that can satisfy its `required_resources`,
  using `Chassis.Inventory.PlacementValidator.check/2`.

  Tracks per-host allocated resources so a single big host that can fit one
  placement isn't double-counted when the next placement needs the same
  resources. Returns `{:error, {:insufficient_capacity, placement}}` for the
  first placement that cannot be fitted onto any remaining host.
  """

  alias Chassis.Inventory.PlacementValidator

  @spec plan(map(), [map()]) :: {:ok, [map()]} | {:error, term()}
  def plan(_profile, []), do: {:error, :no_hosts}

  def plan(%{placements: placements}, hosts) when is_list(hosts) do
    case do_plan(placements, hosts, []) do
      {:ok, assignments} -> {:ok, Enum.reverse(assignments)}
      {:error, _} = err -> err
    end
  end

  defp do_plan([], _hosts, assignments), do: {:ok, assignments}

  defp do_plan([placement | rest], hosts, assignments) do
    case find_fitting_host(placement, hosts) do
      {:ok, host, new_hosts} ->
        assigned = Map.put(placement, :host_ref, host.host_ref)
        do_plan(rest, new_hosts, [assigned | assignments])

      :no_fit ->
        {:error, {:insufficient_capacity, placement}}
    end
  end

  defp find_fitting_host(placement, hosts) do
    required = Map.get(placement, :required_resources, %{})

    case Enum.split_with(hosts, fn host -> PlacementValidator.check(host, required) == :ok end) do
      {[], _} ->
        :no_fit

      {[chosen | other_fitting], non_fitting} ->
        remaining_for_chosen = subtract_resources(chosen, required)
        {:ok, chosen, non_fitting ++ [remaining_for_chosen | other_fitting]}
    end
  end

  defp subtract_resources(host, required) do
    new_resources =
      Enum.reduce(required, host.resources, fn {k, v}, acc ->
        Map.update(acc, k, 0, &(&1 - v))
      end)

    %{host | resources: new_resources}
  end
end

defmodule Chassis.Stack.Composer do
  @moduledoc """
  End-to-end: resolves a profile + env, plans placements against the supplied
  host list, and returns the composed topology with `topology_ref`,
  `profile_ref`, `env`, `adapters`, and `assignments`.
  """

  alias Chassis.Stack.{PlacementPlanner, ProfileResolver}

  @spec compose(String.t(), :dev | :prod, [map()]) :: {:ok, map()} | {:error, term()}
  def compose(profile_ref, env, hosts) do
    with {:ok, resolved} <- ProfileResolver.resolve(profile_ref, env),
         {:ok, assignments} <- PlacementPlanner.plan(resolved, hosts) do
      {:ok,
       %{
         topology_ref: "topology:" <> profile_ref,
         profile_ref: profile_ref,
         env: env,
         adapters: resolved.adapters,
         assignments: assignments
       }}
    end
  end
end
