defmodule Chassis.Environments do
  @moduledoc "Environment profile facade."
end

defmodule Chassis.Environments.Adapter do
  @moduledoc "Behaviour for environment resolution per 0513 §2."
  @callback get_environment(String.t()) :: {:ok, map()} | {:error, term()}
  @callback list_environments() :: {:ok, [map()]}
  @callback resolve(String.t(), :dev | :prod) :: {:ok, map()} | {:error, term()}
end

defmodule Chassis.Environments.FileBasedEnvironments do
  @moduledoc """
  Compile-time embedded provisioning profile catalog per 0513 §3 / §4.

  All four environment JSON files plus `resolver_catalog.json` are loaded at
  compile time via `@external_resource` and `File.read!/1`. The bytes are
  decoded via `Jason.decode!/1` (also at compile time) and frozen into
  module attributes; no `File.read!` is ever called at runtime.

  This satisfies `0503` Phase 6 Spine Audit ("no runtime File.read of
  profile JSON") and means the BEAM binary contains every JSON byte —
  verifiable via `:beam_lib.chunks/2` or by scanning the .beam file.
  """
  @behaviour Chassis.Environments.Adapter

  @profile_dir Path.expand("../../priv/profiles", __DIR__)

  @env_refs [
    "linode_ubuntu_24_04",
    "digital_ocean_ubuntu_24_04",
    "hetzner_ubuntu_24_04",
    "local_ubuntu_24_04"
  ]

  @env_paths Map.new(@env_refs, fn ref -> {ref, Path.join(@profile_dir, ref <> ".json")} end)
  @catalog_path Path.join(@profile_dir, "resolver_catalog.json")

  for {_ref, path} <- @env_paths do
    @external_resource path
  end

  @external_resource @catalog_path

  @raw_envs Map.new(@env_paths, fn {ref, path} -> {ref, File.read!(path)} end)

  @parsed_envs Map.new(@raw_envs, fn {ref, raw} ->
                 parsed = Jason.decode!(raw)

                 {ref,
                  %{
                    env_config_ref: parsed["env_config_ref"] || ref,
                    os: parsed["os"],
                    provider: parsed["provider"],
                    runtime_versions: parsed["runtime_versions"] || %{},
                    setup_script: parsed["setup_script"] || [],
                    ufw_ports: parsed["ufw_ports"] || [],
                    install_paths: parsed["install_paths"] || %{}
                  }}
               end)

  @raw_catalog File.read!(@catalog_path)
  @catalog Jason.decode!(@raw_catalog)

  @impl true
  @spec list_environments() :: {:ok, [map()]}
  def list_environments do
    {:ok, Enum.map(@env_refs, &Map.fetch!(@parsed_envs, &1))}
  end

  @impl true
  @spec get_environment(String.t()) :: {:ok, map()} | {:error, :unknown_environment}
  def get_environment(ref) do
    case Map.fetch(@parsed_envs, ref) do
      {:ok, env} -> {:ok, env}
      :error -> {:error, :unknown_environment}
    end
  end

  @impl true
  @spec resolve(String.t(), :dev | :prod) :: {:ok, map()} | {:error, term()}
  def resolve(profile_ref, env) when env in [:dev, :prod] do
    case Map.fetch(@catalog, profile_ref) do
      {:ok, env_map} ->
        case Map.fetch(env_map, Atom.to_string(env)) do
          {:ok, env_ref} -> get_environment(env_ref)
          :error -> {:error, {:unknown_environment, env}}
        end

      :error ->
        {:error, :unknown_profile}
    end
  end

  def resolve(_profile_ref, env), do: {:error, {:unknown_environment, env}}

  @doc """
  Returns the raw bytes of an embedded JSON profile. Useful for byte-stable
  cross-host verification.
  """
  @spec embedded_json(String.t()) :: String.t()
  def embedded_json("resolver_catalog"), do: @raw_catalog
  def embedded_json(ref), do: Map.fetch!(@raw_envs, ref)

  @doc "List of every embedded `env_config_ref`."
  @spec environment_refs() :: [String.t()]
  def environment_refs, do: @env_refs

  @doc "The decoded resolver catalog (profile_ref -> %{\"dev\" => env_ref, \"prod\" => env_ref})."
  @spec resolver_catalog() :: map()
  def resolver_catalog, do: @catalog
end
