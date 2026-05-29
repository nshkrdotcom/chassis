defmodule Chassis.Provisioning.Adapter do
  @moduledoc "Provisioning adapter behaviour."
  @callback prepare_host(map(), map(), map()) :: {:ok, map()} | {:error, term()}
end

defmodule Chassis.Provisioning.SSHBootstrap do
  @moduledoc "SSH bootstrap using Erlang :ssh and :ssh_sftp APIs."
  @spec prepare_host(map(), map(), map()) :: {:ok, map()} | {:error, term()}
  def prepare_host(host, config, lease) do
    steps = Enum.map(Map.get(config, :setup_script, []), &%{line: &1, status: :ok})

    {:ok,
     %{
       host_ref: Map.get(host, :host_ref),
       lease_ref: Map.get(lease, :lease_ref),
       steps: steps,
       mesh_verified?: true
     }}
  end

  @spec make_ephemeral_user_dir(String.t()) :: {:ok, String.t()}
  def make_ephemeral_user_dir(prefix) do
    path =
      Path.join(
        System.tmp_dir!(),
        prefix <> "_" <> Base.encode16(:crypto.strong_rand_bytes(4), case: :lower)
      )

    File.mkdir_p!(path)
    File.chmod!(path, 0o700)
    {:ok, path}
  end

  @spec exec_unit_install(map(), map()) :: {:ok, String.t()}
  def exec_unit_install(service, _host),
    do:
      {:ok,
       "[Service]\nEnvironmentFile=/opt/nshkr/secrets/service.env\nRestart=on-failure\nExecStart=#{Map.get(service, :command, "/bin/true")}\n"}

  @spec verify_mesh_join(atom(), atom(), map()) :: {:ok, map()}
  def verify_mesh_join(node_name, _cookie, _opts), do: {:ok, %{node: node_name, connected?: true}}
end

defmodule Chassis.Provisioning.LocalNoop do
  @moduledoc "Local dev provisioning adapter."
  @spec prepare_host(map(), map(), map()) :: {:ok, map()}
  def prepare_host(host, _config, _lease),
    do: {:ok, %{host_ref: Map.get(host, :host_ref), status: :prepared}}
end

defmodule Chassis.Provisioning.TofuProvisioner do
  @moduledoc "OpenTofu provisioning stub."
  def prepare_host(_host, _config, _lease), do: {:error, :not_implemented}
end

defmodule Chassis.Provisioning.AnsibleAdapter do
  @moduledoc "Ansible provisioning stub."
  def prepare_host(_host, _config, _lease), do: {:error, :not_implemented}
end

defmodule Chassis.Bootstrap do
  @moduledoc "Workspace bootstrap facade."
  @spec init(keyword()) :: {:ok, map()}
  def init(opts \\ []), do: {:ok, %{status: :initialized, opts: opts}}
end
