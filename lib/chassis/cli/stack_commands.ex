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

  @spec deploy_direct([String.t()], map()) :: {:ok, map()} | {:error, term()}
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

  @spec deploy_mezzanine([String.t()], map()) :: {:ok, map()} | {:error, term()}
  def deploy_mezzanine(positional, switches) do
    app_atom = app_atom(positional)
    profile_ref = profile_ref(switches)
    env = env(switches)
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
      issued_at: DateTime.utc_now(),
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

  @spec transaction_attrs([String.t()], map()) :: map()
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

  @spec maybe_put_hosts(map(), map()) :: map()
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

  @spec hosts(map()) :: [map()] | {:error, term()}
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

  @spec app_atom([String.t()]) :: atom()
  def app_atom([name | _]) do
    name
    |> String.replace("-", "_")
    |> String.to_atom()
  end

  def app_atom([]), do: :extravaganza

  @spec profile_ref(map()) :: String.t()
  def profile_ref(switches), do: Map.get(switches, :profile, "profile:monolith")

  @spec env(map()) :: atom() | String.t()
  def env(switches) do
    case Map.get(switches, :env, "dev") do
      :dev -> :dev
      :prod -> :prod
      "dev" -> :dev
      "prod" -> :prod
      other -> other
    end
  end

  @spec tenant_ref(map()) :: String.t()
  def tenant_ref(switches), do: Map.get(switches, :tenant, "tenant:dev")

  @spec installation_ref(map()) :: String.t()
  def installation_ref(switches), do: Map.get(switches, :installation, "installation:dev")

  @spec idempotency_key(map(), atom(), String.t(), atom() | String.t()) :: String.t()
  def idempotency_key(switches, app_atom, profile_ref, env) do
    Map.get(
      switches,
      :idempotency_key,
      "cli:#{Atom.to_string(app_atom)}:#{profile_ref}:#{env}:#{tenant_ref(switches)}"
    )
  end

  @spec app_row(Chassis.AppRegistry.Entry.t()) :: map()
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

  @spec find_host(String.t(), map()) :: {:ok, map()} | {:error, term()}
  def find_host(host_ref, switches) do
    with hosts when is_list(hosts) <- hosts(switches),
         host when not is_nil(host) <- Enum.find(hosts, &(&1.host_ref == host_ref)) do
      {:ok, host}
    else
      {:error, _reason} = error -> error
      nil -> {:error, {:host_not_found, host_ref}}
    end
  end

  @spec command_error(term()) :: {:error, map()}
  def command_error(reason), do: {:error, %{reason: inspect(reason)}}

  @spec plain(term()) :: term()
  def plain(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  def plain(%_{} = struct), do: struct |> Map.from_struct() |> plain()
  def plain(map) when is_map(map), do: Map.new(map, fn {k, v} -> {k, plain(v)} end)
  def plain(list) when is_list(list), do: Enum.map(list, &plain/1)
  def plain(value), do: value

  defp filter_tenant(hosts, nil), do: hosts

  defp filter_tenant(hosts, tenant_ref) do
    Enum.filter(hosts, &(tenant_ref in Map.get(&1, :tenant_refs, [])))
  end
end

defmodule Chassis.CLI.Command.Stack.Deploy do
  @moduledoc "Deploy a stack through Mezzanine by default, or StackManager with --no-mezzanine."

  @spec run([String.t()], map()) :: {:ok, map()} | {:error, term()}
  def run(positional, switches), do: Chassis.CLI.CommandSupport.deploy(positional, switches)
end

defmodule Chassis.CLI.Command.App.Deploy do
  @moduledoc "Deploy an app through the same stack deployment transaction path."

  @spec run([String.t()], map()) :: {:ok, map()} | {:error, term()}
  def run(positional, switches), do: Chassis.CLI.CommandSupport.deploy(positional, switches)
end

defmodule Chassis.CLI.Command.Stack.Status do
  @moduledoc "List deployment status rows from the app registry."

  alias Chassis.CLI.{CommandSupport, Runtime}

  @spec run([String.t()], map()) :: {:ok, map()} | {:error, term()}
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

  alias Chassis.CLI.{CommandSupport, Runtime}

  @spec run([String.t()], map()) :: {:ok, map()} | {:error, term()}
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

  alias Chassis.CLI.{CommandSupport, Runtime}

  @spec run([String.t()], map()) :: {:ok, map()} | {:error, term()}
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

  @spec run([String.t()], map()) :: {:ok, map()} | {:error, term()}
  def run(positional, switches), do: Chassis.CLI.Command.Stack.Rollback.run(positional, switches)
end

defmodule Chassis.CLI.Command.Stack.Diff do
  @moduledoc "Diff two stack profiles by comparing placement keys."

  alias Chassis.CLI.CommandSupport

  @spec run([String.t()], map()) :: {:ok, map()} | {:error, term()}
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

  alias Chassis.CLI.CommandSupport

  @spec run([String.t()], map()) :: {:ok, map()} | {:error, term()}
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

  alias Chassis.CLI.CommandSupport

  @spec run([String.t()], map()) :: {:ok, map()} | {:error, term()}
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

  alias Chassis.CLI.CommandSupport

  @spec run([String.t()], map()) :: {:ok, map()} | {:error, term()}
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
