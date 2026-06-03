defmodule Chassis.CLI.CommandSupport do
  @moduledoc false

  alias Chassis.CLI.Runtime

  @spec deploy([String.t()], map()) :: {:ok, map()} | {:error, term()}
  def deploy(positional, switches) do
    if Map.get(switches, :no_mezzanine, false) do
      deploy_direct(positional, switches)
    else
      deploy_mezzanine(positional, switches)
    end
  end

  def deploy_direct(positional, switches) do
    attrs =
      positional
      |> transaction_attrs(switches)
      |> maybe_put_hosts(switches)

    case Chassis.StackManager.Transaction.run(attrs) do
      {:ok, result} -> {:ok, result |> Map.put(:via, :direct) |> plain()}
      {:error, reason} -> command_error(reason)
    end
  end

  def deploy_mezzanine(positional, switches) do
    app_atom = app_atom(positional)
    profile_ref = profile_ref(switches)
    env = env(switches)
    now = DateTime.utc_now()
    idempotency_key = idempotency_key(switches, app_atom, profile_ref, env)

    request = %Chassis.Boundary.MaterializeDeployment.Request{
      topology_ref: profile_ref,
      service_spec_ref: "service:" <> Atom.to_string(app_atom),
      runtime_profile_ref: profile_ref,
      placement_ref: "placement:" <> profile_ref,
      environment: env,
      git_sha: Map.get(switches, :git_sha, "unknown"),
      release_version: Map.get(switches, :release_version, "dev")
    }

    envelope_attrs = %{
      envelope_ref: "env:cli:stack.deploy:" <> idempotency_key,
      tenant_ref: tenant_ref(switches),
      installation_ref: installation_ref(switches),
      actor_ref: "operator:cli",
      system_actor_ref: "system:chassis_cli",
      authority_ref: "authority:cli:implicit",
      idempotency_key: idempotency_key,
      trace_id: "trace:cli:" <> idempotency_key,
      issued_at: now,
      status: :request
    }

    opts = [
      app_atom: app_atom,
      registry: Runtime.registry(),
      receipts_store: Runtime.receipts_store(),
      fence_store: Runtime.fence_store(),
      outbox: Runtime.outbox()
    ]

    case Chassis.Mezzanine.Bridge.dispatch(:materialize_deployment, request, envelope_attrs, opts) do
      {:ok, %{payload: response, receipt_refs: receipt_refs}} ->
        {:ok,
         %{
           via: :mezzanine,
           status: :active,
           deployment_receipt_ref: response.deployment_receipt_ref,
           app_ref: response.app_ref,
           node_mesh: response.node_mesh,
           receipt_refs: receipt_refs
         }}

      {:error, reason} ->
        command_error(reason)
    end
  end

  def transaction_attrs(positional, switches) do
    app_atom = app_atom(positional)
    profile_ref = profile_ref(switches)
    env = env(switches)

    %{
      app_atom: app_atom,
      registry: Runtime.registry(),
      receipts_store: Runtime.receipts_store(),
      fence_store: Runtime.fence_store(),
      checkpoint_store: Runtime.checkpoint_store(),
      profile_ref: profile_ref,
      env: env,
      tenant_ref: tenant_ref(switches),
      installation_ref: installation_ref(switches),
      authority_ref: "authority:cli:implicit",
      idempotency_key: idempotency_key(switches, app_atom, profile_ref, env),
      trace_id: "trace:cli:" <> idempotency_key(switches, app_atom, profile_ref, env),
      git_sha: Map.get(switches, :git_sha, "unknown"),
      release_version: Map.get(switches, :release_version, "dev"),
      residency_ref: Map.get(switches, :residency, "residency:global"),
      isolation_profile_ref: Map.get(switches, :isolation, "isolation:dev-shared"),
      quota_ref: Map.get(switches, :quota, "quota:tenant:enterprise")
    }
  end

  def maybe_put_hosts(attrs, switches) do
    case Map.get(switches, :hosts) do
      nil ->
        attrs

      path ->
        Map.put(attrs, :discover_hosts, fn ->
          Chassis.Inventory.StaticDiscovery.discover_hosts(
            path: path,
            tenant_ref: Map.get(switches, :tenant)
          )
        end)
    end
  end

  def app_atom([name | _]) do
    name
    |> String.replace("-", "_")
    |> String.to_atom()
  end

  def app_atom([]), do: :extravaganza

  def profile_ref(switches), do: Map.get(switches, :profile, "profile:monolith")

  def env(switches) do
    case Map.get(switches, :env, "dev") do
      :dev -> :dev
      :prod -> :prod
      "dev" -> :dev
      "prod" -> :prod
      other -> other
    end
  end

  def tenant_ref(switches), do: Map.get(switches, :tenant, "tenant:dev")
  def installation_ref(switches), do: Map.get(switches, :installation, "installation:dev")

  def idempotency_key(switches, app_atom, profile_ref, env) do
    Map.get(
      switches,
      :idempotency_key,
      "cli:#{Atom.to_string(app_atom)}:#{profile_ref}:#{env}:#{tenant_ref(switches)}"
    )
  end

  def hosts(switches) do
    case Map.get(switches, :hosts) do
      nil ->
        Chassis.Inventory.fixture_hosts()
        |> filter_tenant(Map.get(switches, :tenant))

      path ->
        with {:ok, hosts} <-
               Chassis.Inventory.StaticDiscovery.discover_hosts(
                 path: path,
                 tenant_ref: Map.get(switches, :tenant)
               ) do
          hosts
        end
    end
  end

  def key_opts(switches) do
    []
    |> maybe_put(:vault_path, Map.get(switches, :vault_path))
    |> maybe_put_plaintext_backend(Map.get(switches, :plaintext_vault, false))
  end

  def material_from_file(switches) do
    case Map.get(switches, :material_file) do
      nil -> {:error, :material_file_required}
      path -> File.read(path)
    end
  end

  def command_error(reason), do: {:error, %{reason: inspect(reason)}}

  def plain(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  def plain(%_{} = struct), do: struct |> Map.from_struct() |> plain()
  def plain(map) when is_map(map), do: Map.new(map, fn {k, v} -> {k, plain(v)} end)
  def plain(list) when is_list(list), do: Enum.map(list, &plain/1)
  def plain(value), do: value

  def app_row(entry) do
    entry
    |> plain()
    |> Map.take([
      :app_ref,
      :app_atom,
      :tenant_ref,
      :active_profile,
      :environment,
      :status,
      :last_deployment_receipt_ref
    ])
  end

  def find_host(host_ref, switches) do
    with hosts when is_list(hosts) <- hosts(switches),
         host when not is_nil(host) <- Enum.find(hosts, &(&1.host_ref == host_ref)) do
      {:ok, host}
    else
      {:error, _reason} = error -> error
      nil -> {:error, {:host_not_found, host_ref}}
    end
  end

  defp filter_tenant(hosts, nil), do: hosts

  defp filter_tenant(hosts, tenant_ref) do
    Enum.filter(hosts, &(tenant_ref in Map.get(&1, :tenant_refs, [])))
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp maybe_put_plaintext_backend(opts, true),
    do: Keyword.put(opts, :crypto_backend, Chassis.CLI.PlaintextVaultBackend)

  defp maybe_put_plaintext_backend(opts, _), do: opts
end

defmodule Chassis.CLI.Table do
  @moduledoc false

  @spec render([atom()], [map()]) :: String.t()
  def render(columns, rows) do
    widths = widths(columns, rows)

    header =
      columns
      |> Enum.map(&pad(String.upcase(to_string(&1)), widths[&1]))
      |> Enum.join("  ")

    body =
      rows
      |> Enum.map(fn row ->
        columns
        |> Enum.map(&pad(format_cell(Map.get(row, &1)), widths[&1]))
        |> Enum.join("  ")
      end)

    [
      Bunt.ANSI.format([:bright, :cyan, header], true),
      Enum.map_join(columns, "  ", &String.duplicate("-", widths[&1])) | body
    ]
    |> Enum.join("\n")
  end

  defp widths(columns, rows) do
    Map.new(columns, fn column ->
      width =
        rows
        |> Enum.map(&(Map.get(&1, column) |> format_cell() |> String.length()))
        |> Enum.max(fn -> 0 end)
        |> max(String.length(to_string(column)))

      {column, width}
    end)
  end

  defp format_cell(nil), do: ""
  defp format_cell(value) when is_atom(value), do: Atom.to_string(value)
  defp format_cell(value), do: to_string(value)
  defp pad(value, width), do: value <> String.duplicate(" ", max(width - String.length(value), 0))
end

defmodule Chassis.CLI.Command.Stack.Deploy do
  @moduledoc "Deploy a stack through Mezzanine by default, or StackManager with --no-mezzanine."
  @behaviour Chassis.CLI.Command

  @impl true
  def run(positional, switches), do: Chassis.CLI.CommandSupport.deploy(positional, switches)
end

defmodule Chassis.CLI.Command.App.Deploy do
  @moduledoc "Deploy an app through the same stack deployment transaction path."
  @behaviour Chassis.CLI.Command

  @impl true
  def run(positional, switches), do: Chassis.CLI.CommandSupport.deploy(positional, switches)
end

defmodule Chassis.CLI.Command.Stack.Status do
  @moduledoc "List deployment status rows from the app registry."
  @behaviour Chassis.CLI.Command

  alias Chassis.CLI.{CommandSupport, Runtime}

  @impl true
  def run(_positional, _switches) do
    with {:ok, entries} <- Chassis.AppRegistry.list(Runtime.registry(), []) do
      rows = Enum.map(entries, &CommandSupport.app_row/1)

      {:ok,
       %{
         format: :table,
         columns: [:app_ref, :app_atom, :tenant_ref, :active_profile, :environment, :status],
         rows: rows,
         count: length(rows)
       }}
    end
  end
end

defmodule Chassis.CLI.Command.App.List do
  @moduledoc "List deployed applications from the app registry."
  @behaviour Chassis.CLI.Command

  alias Chassis.CLI.{CommandSupport, Runtime}

  @impl true
  def run(_positional, switches) do
    query =
      []
      |> maybe_query(:tenant_ref, Map.get(switches, :tenant))
      |> maybe_query(:environment, CommandSupport.env(switches))

    with {:ok, entries} <- Chassis.AppRegistry.list(Runtime.registry(), query) do
      rows = Enum.map(entries, &CommandSupport.app_row/1)

      {:ok,
       %{
         format: :table,
         columns: [:app_ref, :app_atom, :tenant_ref, :active_profile, :environment, :status],
         rows: rows,
         count: length(rows)
       }}
    end
  end

  defp maybe_query(query, _key, nil), do: query
  defp maybe_query(query, key, value), do: Keyword.put(query, key, value)
end

defmodule Chassis.CLI.Command.Stack.Rollback do
  @moduledoc "Rollback a deployed app through StackManager.Transaction.rollback/2."
  @behaviour Chassis.CLI.Command

  alias Chassis.CLI.{CommandSupport, Runtime}

  @impl true
  def run([app_ref | _], _switches) do
    case Chassis.StackManager.Transaction.rollback(app_ref,
           registry: Runtime.registry(),
           receipts_store: Runtime.receipts_store(),
           checkpoint_store: Runtime.checkpoint_store(),
           authority_ref: "authority:cli:implicit"
         ) do
      {:ok, result} -> {:ok, CommandSupport.plain(result)}
      {:error, reason} -> CommandSupport.command_error(reason)
    end
  end

  def run(_positional, _switches), do: CommandSupport.command_error(:app_ref_required)
end

defmodule Chassis.CLI.Command.App.Rollback do
  @moduledoc "Rollback a deployed app."
  @behaviour Chassis.CLI.Command

  @impl true
  def run(positional, switches), do: Chassis.CLI.Command.Stack.Rollback.run(positional, switches)
end

defmodule Chassis.CLI.Command.Stack.Diff do
  @moduledoc "Diff two stack profiles by comparing placement keys."
  @behaviour Chassis.CLI.Command

  alias Chassis.CLI.CommandSupport

  @impl true
  def run(positional, switches) do
    from = Map.get(switches, :from) || Enum.at(positional, 0) || "profile:monolith"
    to = Map.get(switches, :to) || Enum.at(positional, 1) || "profile:ternary-split-3"

    with {:ok, from_profile} <- Chassis.Stack.ConfigurationProfile.get(from),
         {:ok, to_profile} <- Chassis.Stack.ConfigurationProfile.get(to) do
      from_keys = placement_keys(from_profile)
      to_keys = placement_keys(to_profile)

      {:ok,
       %{
         from: from,
         to: to,
         added: MapSet.difference(to_keys, from_keys) |> MapSet.to_list(),
         removed: MapSet.difference(from_keys, to_keys) |> MapSet.to_list(),
         unchanged: MapSet.intersection(from_keys, to_keys) |> MapSet.to_list()
       }}
    else
      {:error, reason} -> CommandSupport.command_error(reason)
    end
  end

  defp placement_keys(%{placements: placements}) do
    placements
    |> Enum.map(&Map.get(&1, :node_name_pattern))
    |> MapSet.new()
  end
end

defmodule Chassis.CLI.Command.Host.Inventory do
  @moduledoc "Discover hosts through inventory package logic."
  @behaviour Chassis.CLI.Command

  alias Chassis.CLI.CommandSupport

  @impl true
  def run(_positional, switches) do
    case CommandSupport.hosts(switches) do
      hosts when is_list(hosts) ->
        {:ok, %{hosts: CommandSupport.plain(hosts), count: length(hosts)}}

      {:error, reason} ->
        CommandSupport.command_error(reason)
    end
  end
end

defmodule Chassis.CLI.Command.Host.Inspect do
  @moduledoc "Inspect a host using inventory plus doctor host diagnostics."
  @behaviour Chassis.CLI.Command

  alias Chassis.CLI.CommandSupport

  @impl true
  def run([host_ref | _], switches) do
    with {:ok, host} <- CommandSupport.find_host(host_ref, switches),
         {:ok, result} <- Chassis.Doctor.HostDiagnostics.check(host) do
      {:ok, %{host: CommandSupport.plain(result)}}
    else
      {:error, reason} -> CommandSupport.command_error(reason)
    end
  end

  def run(_positional, _switches), do: CommandSupport.command_error(:host_ref_required)
end

defmodule Chassis.CLI.Command.Node.Doctor do
  @moduledoc "Run node diagnostics through Chassis.Doctor."
  @behaviour Chassis.CLI.Command

  alias Chassis.CLI.CommandSupport

  @impl true
  def run([node_ref | _], _switches) do
    with {:ok, result} <- Chassis.Doctor.NodeDiagnostics.check(node_ref) do
      {:ok, %{node: CommandSupport.plain(result)}}
    end
  end

  def run(_positional, _switches) do
    case Chassis.Doctor.run() do
      {:ok, report} -> {:ok, %{status: :healthy, report: CommandSupport.plain(report)}}
      {:error, report} -> {:error, %{reason: inspect(report)}}
    end
  end
end

defmodule Chassis.CLI.Command.Node.Bootstrap do
  @moduledoc "Prepare a node through the local bootstrap adapter."
  @behaviour Chassis.CLI.Command

  alias Chassis.CLI.CommandSupport

  @impl true
  def run([host_ref | _], switches) do
    host = %{host_ref: host_ref, status: :online}

    env_ref =
      if CommandSupport.env(switches) == :prod,
        do: "linode_ubuntu_24_04",
        else: "local_ubuntu_24_04"

    with {:ok, env} <- Chassis.Environments.FileBasedEnvironments.get_environment(env_ref),
         {:ok, result} <-
           Chassis.Provisioning.LocalNoop.prepare_host(host, env, %{lease_ref: "lease:cli"}) do
      {:ok, %{host: CommandSupport.plain(result), env_config_ref: env.env_config_ref}}
    else
      {:error, reason} -> CommandSupport.command_error(reason)
    end
  end

  def run(_positional, _switches), do: CommandSupport.command_error(:host_ref_required)
end

defmodule Chassis.CLI.Command.Keys.Add do
  @moduledoc "Add an SSH key through Chassis.Keys.Manager."
  @behaviour Chassis.CLI.Command

  alias Chassis.CLI.CommandSupport

  @impl true
  def run([name | _], switches) do
    with {:ok, material} <- CommandSupport.material_from_file(switches),
         {:ok, result} <-
           Chassis.Keys.Manager.add(name, material, CommandSupport.key_opts(switches)) do
      {:ok, CommandSupport.plain(result)}
    else
      {:error, reason} -> CommandSupport.command_error(reason)
    end
  end

  def run(_positional, _switches), do: CommandSupport.command_error(:key_name_required)
end

defmodule Chassis.CLI.Command.Keys.List do
  @moduledoc "List SSH keys through Chassis.Keys.Manager."
  @behaviour Chassis.CLI.Command

  alias Chassis.CLI.CommandSupport

  @impl true
  def run(_positional, switches) do
    with {:ok, keys} <- Chassis.Keys.Manager.list(CommandSupport.key_opts(switches)) do
      {:ok, %{keys: CommandSupport.plain(keys), count: length(keys)}}
    else
      {:error, reason} -> CommandSupport.command_error(reason)
    end
  end
end

defmodule Chassis.CLI.Command.Keys.Show do
  @moduledoc "Show SSH key metadata through Chassis.Keys.Manager."
  @behaviour Chassis.CLI.Command

  alias Chassis.CLI.CommandSupport

  @impl true
  def run([name | _], switches) do
    with {:ok, key} <- Chassis.Keys.Manager.show(name, CommandSupport.key_opts(switches)) do
      {:ok, CommandSupport.plain(key)}
    else
      {:error, reason} -> CommandSupport.command_error(reason)
    end
  end

  def run(_positional, _switches), do: CommandSupport.command_error(:key_name_required)
end

defmodule Chassis.CLI.Command.Keys.Rotate do
  @moduledoc "Rotate an SSH key through Chassis.Keys.Manager."
  @behaviour Chassis.CLI.Command

  alias Chassis.CLI.CommandSupport

  @impl true
  def run([name | _], switches) do
    with {:ok, material} <- CommandSupport.material_from_file(switches),
         {:ok, key} <-
           Chassis.Keys.Manager.rotate(name, material, CommandSupport.key_opts(switches)) do
      {:ok, CommandSupport.plain(key)}
    else
      {:error, reason} -> CommandSupport.command_error(reason)
    end
  end

  def run(_positional, _switches), do: CommandSupport.command_error(:key_name_required)
end

defmodule Chassis.CLI.Command.Env.List do
  @moduledoc "List embedded environment configs."
  @behaviour Chassis.CLI.Command

  alias Chassis.CLI.CommandSupport

  @impl true
  def run(_positional, _switches) do
    with {:ok, envs} <- Chassis.Environments.FileBasedEnvironments.list_environments() do
      {:ok, %{environments: CommandSupport.plain(envs), count: length(envs)}}
    end
  end
end

defmodule Chassis.CLI.Command.Env.Show do
  @moduledoc "Show one embedded environment config."
  @behaviour Chassis.CLI.Command

  alias Chassis.CLI.CommandSupport

  @impl true
  def run([ref | _], _switches) do
    with {:ok, env} <- Chassis.Environments.FileBasedEnvironments.get_environment(ref) do
      {:ok, %{environment: CommandSupport.plain(env)}}
    else
      {:error, reason} -> CommandSupport.command_error(reason)
    end
  end

  def run(_positional, _switches), do: CommandSupport.command_error(:env_ref_required)
end

defmodule Chassis.CLI.Command.Proof.Run do
  @moduledoc "Phase 21 proof runner placeholder routed through a real command module."
  @behaviour Chassis.CLI.Command

  @impl true
  def run(_positional, _switches),
    do: {:error, {:not_implemented, __MODULE__, [phase: 21, package: :chassis_stacklab_bridge]}}
end

defmodule Chassis.CLI.Command.Evolution.Fixture do
  @moduledoc "Runs a Phase 36 evolution conformance scenario through the proof package."
  @behaviour Chassis.CLI.Command

  alias Chassis.Evolution.Conformance
  alias Chassis.Evolution.Conformance.Evidence

  @impl true
  def run(_positional, switches) do
    case Map.get(switches, :scenario) do
      nil ->
        {:error, %{reason: "missing --scenario"}}

      scenario ->
        opts =
          switches
          |> Map.take([:receipts_dir])
          |> Enum.reject(fn {_key, value} -> is_nil(value) end)

        with {:ok, report} <- Conformance.run(scenario, opts) do
          {:ok, Evidence.jsonable(report)}
        end
    end
  end
end

defmodule Chassis.CLI.Command.Evolution.Proof do
  @moduledoc "Runs the Phase 36 evolution conformance proof harness."
  @behaviour Chassis.CLI.Command

  alias Chassis.Evolution.Conformance
  alias Chassis.Evolution.Conformance.Evidence

  @impl true
  def run(_positional, switches) do
    opts =
      switches
      |> Map.take([
        :app,
        :profile,
        :env,
        :fixture,
        :require_trial,
        :require_citadel_consent,
        :require_health_gated_swap,
        :require_rollback_proof
      ])
      |> Map.to_list()

    with {:ok, report} <- Conformance.proof(opts) do
      {:ok, Evidence.jsonable(report)}
    end
  end
end

defmodule Chassis.CLI.Command.Hardware.Validate do
  @moduledoc "Runs the Phase 37 hardware accelerator admission guard."
  @behaviour Chassis.CLI.Command

  alias Chassis.HardwareGuard

  @impl true
  def run(positional, switches) do
    host_ref = Map.get(switches, :host) || Enum.at(positional, 0)
    runtime_ref = Map.get(switches, :runtime) || Enum.at(positional, 1)

    cond do
      is_nil(host_ref) ->
        {:error, %{reason: "missing --host"}}

      is_nil(runtime_ref) ->
        {:error, %{reason: "missing --runtime"}}

      true ->
        with {:ok, report} <- HardwareGuard.validate(host_ref, runtime_ref) do
          {:ok, HardwareGuard.jsonable(report)}
        end
    end
  end
end
