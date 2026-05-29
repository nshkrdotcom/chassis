defmodule Chassis.Stack do
  @moduledoc "Profile and placement facade."
end

defmodule Chassis.Stack.ConfigurationProfile do
  @moduledoc "Compile-time profile registry."
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

  @spec all() :: map()
  def all, do: @profiles

  @spec get(String.t()) :: {:ok, map()} | {:error, :unknown_profile}
  def get(ref),
    do:
      if(Map.has_key?(@profiles, ref),
        do: {:ok, %{profile_ref: ref, placements: @profiles[ref]}},
        else: {:error, :unknown_profile}
      )
end

defmodule Chassis.Stack.ProfileResolver do
  @moduledoc "Resolves profile and environment into adapter set."
  @spec resolve(String.t(), :dev | :prod) :: {:ok, map()} | {:error, term()}
  def resolve(profile_ref, env) do
    with {:ok, profile} <- Chassis.Stack.ConfigurationProfile.get(profile_ref) do
      adapters =
        if env == :dev do
          %{discovery: :static, provisioning: :local_noop, secrets: :env, mesh: :local_loopback}
        else
          %{discovery: :dynamic, provisioning: :ssh_bootstrap, secrets: :sops, mesh: :beam_tls}
        end

      {:ok, Map.merge(profile, %{env: env, adapters: adapters})}
    end
  end
end

defmodule Chassis.Stack.PlacementPlanner do
  @moduledoc "Maps placements to hosts by host_ref."
  @spec plan(map(), [map()]) :: {:ok, [map()]} | {:error, term()}
  def plan(%{placements: placements}, hosts) do
    host_refs = Enum.map(hosts, &Map.fetch!(&1, :host_ref))

    assignments =
      placements
      |> Enum.with_index()
      |> Enum.map(fn {placement, index} ->
        Map.put(placement, :host_ref, Enum.at(host_refs, rem(index, max(length(host_refs), 1))))
      end)

    {:ok, assignments}
  end
end

defmodule Chassis.Stack.Composer do
  @moduledoc "Composes profile, hosts, and BEAM node descriptors."
  @spec compose(String.t(), :dev | :prod, [map()]) :: {:ok, map()} | {:error, term()}
  def compose(profile_ref, env, hosts) do
    with {:ok, resolved} <- Chassis.Stack.ProfileResolver.resolve(profile_ref, env),
         {:ok, assignments} <- Chassis.Stack.PlacementPlanner.plan(resolved, hosts) do
      {:ok,
       %{
         topology_ref: "topology:" <> profile_ref,
         profile_ref: profile_ref,
         env: env,
         assignments: assignments
       }}
    end
  end
end
