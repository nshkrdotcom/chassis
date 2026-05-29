defmodule Chassis.Environments do
  @moduledoc "Environment profile facade."
end

defmodule Chassis.Environments.Adapter do
  @moduledoc "Behaviour for environment resolution."
  @callback get_environment(String.t()) :: {:ok, map()} | {:error, term()}
  @callback list_environments() :: {:ok, [map()]}
  @callback resolve(String.t(), :dev | :prod) :: {:ok, map()} | {:error, term()}
end

defmodule Chassis.Environments.FileBasedEnvironments do
  @moduledoc "Compile-time embedded environment profiles."

  @profile_dir Path.expand("../../priv/profiles", __DIR__)
  @files %{
    "linode_ubuntu_24_04" => Path.join(@profile_dir, "linode_ubuntu_24_04.json"),
    "digital_ocean_ubuntu_24_04" => Path.join(@profile_dir, "digital_ocean_ubuntu_24_04.json"),
    "hetzner_ubuntu_24_04" => Path.join(@profile_dir, "hetzner_ubuntu_24_04.json"),
    "local_ubuntu_24_04" => Path.join(@profile_dir, "local_ubuntu_24_04.json"),
    "resolver_catalog" => Path.join(@profile_dir, "resolver_catalog.json")
  }

  for {_name, path} <- @files do
    @external_resource path
  end

  @embedded Map.new(@files, fn {name, path} -> {name, File.read!(path)} end)

  @spec list_environments() :: {:ok, [map()]}
  def list_environments do
    {:ok, Enum.map(environment_refs(), &config/1)}
  end

  @spec get_environment(String.t()) :: {:ok, map()} | {:error, :unknown_environment}
  def get_environment(ref)
      when ref in [
             "linode_ubuntu_24_04",
             "digital_ocean_ubuntu_24_04",
             "hetzner_ubuntu_24_04",
             "local_ubuntu_24_04"
           ],
      do: {:ok, config(ref)}

  def get_environment(_ref), do: {:error, :unknown_environment}

  @spec resolve(String.t(), :dev | :prod) :: {:ok, map()}
  def resolve(_profile_ref, :dev), do: {:ok, config("local_ubuntu_24_04")}
  def resolve("profile:ternary-split-3", :prod), do: {:ok, config("linode_ubuntu_24_04")}
  def resolve(_profile_ref, :prod), do: {:ok, config("linode_ubuntu_24_04")}

  @spec embedded_json(String.t()) :: String.t()
  def embedded_json(ref), do: Map.fetch!(@embedded, ref)

  @spec environment_refs() :: [String.t()]
  def environment_refs,
    do: [
      "linode_ubuntu_24_04",
      "digital_ocean_ubuntu_24_04",
      "hetzner_ubuntu_24_04",
      "local_ubuntu_24_04"
    ]

  defp config(ref) do
    provider =
      ref
      |> String.replace("_ubuntu_24_04", "")
      |> String.replace("digital_ocean", "digital_ocean")

    %{
      env_config_ref: ref,
      os: "ubuntu_24_04",
      provider: provider,
      runtime_versions: %{erlang: "28.3", elixir: "1.19.5"},
      setup_script: ["apt-get update", "install erlang elixir", "install chassis host daemon"],
      ufw_ports: ["4369", "9100:9200"],
      install_paths: %{
        release: "/opt/nshkr/releases",
        secrets: "/opt/nshkr/secrets",
        receipts: "/opt/nshkr/receipts"
      }
    }
  end
end
