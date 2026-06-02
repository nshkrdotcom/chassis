defmodule Chassis.Adapter.Systemd do
  @moduledoc """
  Systemd unit template generator and `systemctl` command wrapper.

  Implements `Chassis.Contracts.Adapter`. The wrapper invokes the local
  `systemctl` binary via `System.cmd/2`. Remote systemd operations are
  delegated to `Chassis.Adapter.SSH` (Phase 8 sibling package).
  """
  @behaviour Chassis.Contracts.Adapter

  @doc """
  Render a complete `.service` unit body. Includes
  `EnvironmentFile=/opt/nshkr/secrets/service.env`, `Restart=on-failure`,
  and the supplied `ExecStart` command.
  """
  @spec unit_file(map()) :: String.t()
  def unit_file(service) do
    name = Map.get(service, :name, "nshkr service")
    description = Map.get(service, :description, name)
    cmd = Map.get(service, :command, "/bin/true")
    user = Map.get(service, :user, "nshkr")
    env_file = Map.get(service, :env_file, "/opt/nshkr/secrets/service.env")

    """
    [Unit]
    Description=#{description}
    After=network.target

    [Service]
    Type=simple
    User=#{user}
    EnvironmentFile=#{env_file}
    Restart=on-failure
    RestartSec=5
    ExecStart=#{cmd}

    [Install]
    WantedBy=multi-user.target
    """
  end

  @doc """
  Run a `systemctl` subcommand locally. `args` is appended after `subcommand`.
  Returns `{:ok, %{stdout, exit_status}}` or `{:error, reason}`.
  """
  @spec systemctl(String.t(), [String.t()], keyword()) ::
          {:ok, map()} | {:error, term()}
  def systemctl(subcommand, args \\ [], opts \\ []) do
    cmd = Keyword.get(opts, :cmd_module, System)
    bin = Keyword.get(opts, :bin, "systemctl")

    case cmd.cmd(bin, [subcommand | args], stderr_to_stdout: true) do
      {output, status} -> {:ok, %{stdout: output, exit_status: status}}
    end
  rescue
    e in ErlangError ->
      case e do
        %ErlangError{original: :enoent} -> {:error, :systemctl_not_found}
        _ -> {:error, {:systemctl_error, Exception.message(e)}}
      end
  end

  @impl true
  def prepare(payload, _opts), do: {:ok, Map.put(payload, :unit_file, unit_file(payload))}

  @impl true
  def start(payload, opts) do
    name = Keyword.get(opts, :unit_name) || Map.get(payload, :unit_name)
    if is_nil(name), do: {:error, :missing_unit_name}, else: do_systemctl(payload, "start", name, opts, :started)
  end

  @impl true
  def stop(payload, opts) do
    name = Keyword.get(opts, :unit_name) || Map.get(payload, :unit_name)
    if is_nil(name), do: {:error, :missing_unit_name}, else: do_systemctl(payload, "stop", name, opts, :stopped)
  end

  @impl true
  def health(payload, opts) do
    name = Keyword.get(opts, :unit_name) || Map.get(payload, :unit_name)

    if is_nil(name) do
      {:error, :missing_unit_name}
    else
      case systemctl("is-active", [name], opts) do
        {:ok, %{stdout: out, exit_status: 0}} ->
          {:ok, Map.put(payload, :status, parse_active(out))}

        {:ok, %{stdout: out, exit_status: _}} ->
          {:ok, Map.put(payload, :status, parse_active(out))}

        err ->
          err
      end
    end
  end

  defp do_systemctl(payload, action, name, opts, status_atom) do
    case systemctl(action, [name], opts) do
      {:ok, %{exit_status: 0}} -> {:ok, Map.put(payload, :status, status_atom)}
      {:ok, %{exit_status: code, stdout: out}} -> {:error, {:systemctl_nonzero, code, out}}
      err -> err
    end
  end

  defp parse_active(out) do
    out
    |> String.trim()
    |> String.downcase()
    |> case do
      "active" -> :active
      "inactive" -> :inactive
      "failed" -> :failed
      "activating" -> :activating
      other -> {:unknown, other}
    end
  end
end

defmodule Chassis.Systemd do
  @moduledoc "Compatibility facade."
end
