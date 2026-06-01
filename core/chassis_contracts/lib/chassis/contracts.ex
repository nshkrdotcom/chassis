defmodule Chassis.Contracts do
  @moduledoc """
  Pure DTO schemas, canonical boundary codec, and redaction helpers for the
  NSHKR Spatial Plane.

  This module is the **only** Chassis package allowed to define cross-plane
  contract structs. Receipts, adapters, the CLI, and downstream packages
  must consume these structs — never re-define them.

  All canonical encoding goes through `Chassis.Contracts.encode/1`, which is
  deterministic and refuses to encode payloads containing PIDs, references,
  functions, or atoms that look like sensitive material. See §5 of
  `0541_implementation_readiness_corrections.md` for the redaction contract.
  """

  @doc """
  Canonical JSON encoder. Always serializes map keys in lexicographic order
  so the same struct produces byte-identical output across calls. Refuses
  PIDs, references, ports, and functions.
  """
  @spec encode(term()) :: {:ok, String.t()} | {:error, term()}
  def encode(value) do
    with {:ok, normalized} <- normalize(value) do
      {:ok, canonical_json(normalized)}
    end
  end

  @doc """
  Bang variant of `encode/1`. Raises `ArgumentError` on unsupported payloads.
  """
  @spec encode!(term()) :: String.t()
  def encode!(value) do
    case encode(value) do
      {:ok, json} -> json
      {:error, reason} -> raise ArgumentError, "unsupported contracts payload: #{inspect(reason)}"
    end
  end

  @doc """
  Decode a previously-encoded canonical JSON string back into a value with
  binary keys. **Never** creates atoms from external input.
  """
  @spec decode(String.t()) :: {:ok, term()} | {:error, term()}
  def decode(binary) when is_binary(binary), do: Jason.decode(binary)

  @doc """
  Backwards-compat helper used by some packages: round-trips a value through
  ETF. Retained because removing it would be a public-API break in other
  Chassis packages classified as `useful_incomplete_source` in
  `recovery_baseline.md`.
  """
  @spec round_trip(term()) :: term()
  def round_trip(value), do: value |> :erlang.term_to_binary() |> :erlang.binary_to_term()

  @doc """
  Replace the tenant_ref inside a `NSHKR.Tenant.TenantContext` with a stable
  SHA-256 token. Idempotent: a context whose tenant_ref already starts with
  `tenant:hashed:` is returned unchanged.
  """
  @spec redact_tenant_context(NSHKR.Tenant.TenantContext.t()) :: NSHKR.Tenant.TenantContext.t()
  def redact_tenant_context(%_{tenant_ref: tref, installation_ref: _iref} = ctx) do
    if is_binary(tref) and String.starts_with?(tref, "tenant:hashed:") do
      ctx
    else
      digest = :crypto.hash(:sha256, tref || "") |> Base.encode16(case: :lower) |> binary_part(0, 16)
      %{ctx | tenant_ref: "tenant:hashed:" <> digest}
    end
  end

  # --- Canonical normalization ---

  defp normalize(value) when is_struct(value) do
    value |> Map.from_struct() |> normalize()
  end

  defp normalize(value) when is_map(value) do
    Enum.reduce_while(value, {:ok, %{}}, fn {k, v}, {:ok, acc} ->
      case {normalize_key(k), normalize(v)} do
        {{:ok, k2}, {:ok, v2}} -> {:cont, {:ok, Map.put(acc, k2, v2)}}
        {{:error, reason}, _} -> {:halt, {:error, reason}}
        {_, {:error, reason}} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp normalize(value) when is_list(value) do
    Enum.reduce_while(value, {:ok, []}, fn v, {:ok, acc} ->
      case normalize(v) do
        {:ok, v2} -> {:cont, {:ok, [v2 | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, reversed} -> {:ok, Enum.reverse(reversed)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp normalize(value) when is_binary(value), do: {:ok, value}
  defp normalize(value) when is_boolean(value), do: {:ok, value}
  defp normalize(nil), do: {:ok, nil}
  defp normalize(value) when is_integer(value) or is_float(value), do: {:ok, value}
  defp normalize(value) when is_atom(value), do: {:ok, Atom.to_string(value)}
  defp normalize(value) when is_pid(value), do: {:error, {:unsupported_pid, inspect(value)}}
  defp normalize(value) when is_reference(value), do: {:error, {:unsupported_reference, inspect(value)}}
  defp normalize(value) when is_port(value), do: {:error, {:unsupported_port, inspect(value)}}
  defp normalize(value) when is_function(value), do: {:error, {:unsupported_function, inspect(value)}}
  defp normalize(value) when is_tuple(value),
    do: {:error, {:unsupported_tuple, "tuples must be encoded as lists, got #{inspect(value)}"}}

  defp normalize(other), do: {:error, {:unsupported_term, inspect(other)}}

  defp normalize_key(k) when is_binary(k), do: {:ok, k}
  defp normalize_key(k) when is_atom(k) and not is_nil(k) and not is_boolean(k),
    do: {:ok, Atom.to_string(k)}
  defp normalize_key(k), do: {:error, {:unsupported_map_key, inspect(k)}}

  # Stable, deterministic JSON: keys sorted, no whitespace.
  defp canonical_json(value) when is_map(value) do
    parts =
      value
      |> Map.to_list()
      |> Enum.sort_by(fn {k, _v} -> k end)
      |> Enum.map(fn {k, v} -> Jason.encode!(k) <> ":" <> canonical_json(v) end)

    "{" <> Enum.join(parts, ",") <> "}"
  end

  defp canonical_json(value) when is_list(value) do
    "[" <> Enum.map_join(value, ",", &canonical_json/1) <> "]"
  end

  defp canonical_json(value), do: Jason.encode!(value)
end

defmodule Chassis.Contracts.StackTopology do
  @moduledoc "Resolved stack topology emitted by `chassis_stack`."
  @enforce_keys [:topology_ref, :profile_ref, :nodes]
  defstruct [:topology_ref, :profile_ref, :tenant_ref, nodes: [], services: [], metadata: %{}]

  @type t :: %__MODULE__{
          topology_ref: String.t(),
          profile_ref: String.t(),
          tenant_ref: String.t() | nil,
          nodes: [map()],
          services: [map()],
          metadata: map()
        }
end

defmodule Chassis.Contracts.ServiceSpec do
  @moduledoc "Service runtime manifest."
  @enforce_keys [:service_ref, :app_ref, :runtime_profile_ref, :command]
  defstruct [
    :service_ref,
    :app_ref,
    :runtime_profile_ref,
    :command,
    env_files: [],
    args: [],
    ports: []
  ]

  @type t :: %__MODULE__{
          service_ref: String.t(),
          app_ref: String.t(),
          runtime_profile_ref: String.t(),
          command: String.t(),
          env_files: [String.t()],
          args: [String.t()],
          ports: [pos_integer()]
        }
end

defmodule Chassis.Contracts.InstallationManifest do
  @moduledoc "Install paths, deps, OS packages, systemd unit, and release bundle."
  @enforce_keys [:installation_ref, :release_tarball_path]
  defstruct [
    :installation_ref,
    :release_tarball_path,
    :systemd_unit_name,
    paths: %{},
    deps: [],
    os_packages: []
  ]

  @type t :: %__MODULE__{
          installation_ref: String.t(),
          release_tarball_path: String.t(),
          systemd_unit_name: String.t() | nil,
          paths: map(),
          deps: [String.t()],
          os_packages: [String.t()]
        }
end

defmodule Chassis.Contracts.ComponentManifest do
  @moduledoc "Logical virtual-server component signature."
  @enforce_keys [:component_ref, :virtual_server, :service_specs]
  defstruct [:component_ref, :virtual_server, service_specs: [], required_capabilities: %{}]

  @type t :: %__MODULE__{
          component_ref: String.t(),
          virtual_server: atom(),
          service_specs: [Chassis.Contracts.ServiceSpec.t()],
          required_capabilities: map()
        }
end

defmodule Chassis.Contracts.ConfigurationProfile do
  @moduledoc "Maps virtual servers to BEAM nodes for a topology."
  defstruct [:profile_ref, :name, placements: []]

  @type vs_atom ::
          :vs_app_kit
          | :vs_mezzanine
          | :vs_outer_brain
          | :vs_citadel
          | :vs_jido_integration
          | :vs_execution_plane
          | :vs_secrets_plane
          | :vs_observability

  @type placement :: %{
          node_name_pattern: String.t(),
          virtual_servers: [vs_atom()],
          required_resources: map()
        }

  @type t :: %__MODULE__{
          profile_ref: String.t() | nil,
          name: String.t() | nil,
          placements: [placement()]
        }
end

defmodule Chassis.Contracts.PhysicalHost do
  @moduledoc """
  Physical host descriptor. `host_ref` is the canonical join key.

  Includes a `defimpl Inspect` so a host with `ssh_key_ref` never leaks the
  key material through `IO.inspect` or process exit reasons.
  """
  defstruct [
    :host_ref,
    :hostname,
    :ip_address,
    :ssh_port,
    :ssh_user,
    :ssh_key_ref,
    resources: %{},
    region: nil,
    provider: nil,
    status: :unknown,
    tenant_refs: []
  ]

  @type t :: %__MODULE__{
          host_ref: String.t() | nil,
          hostname: String.t() | nil,
          ip_address: String.t() | nil,
          ssh_port: pos_integer() | nil,
          ssh_user: String.t() | nil,
          ssh_key_ref: String.t() | nil,
          resources: map(),
          region: String.t() | nil,
          provider: atom() | String.t() | nil,
          status: atom(),
          tenant_refs: [String.t()]
        }

  defimpl Inspect do
    import Inspect.Algebra

    def inspect(host, opts) do
      masked = %{host | ssh_key_ref: redact_ssh_key(host.ssh_key_ref)}
      concat(["%Chassis.Contracts.PhysicalHost{", to_doc(Map.from_struct(masked), opts), "}"])
    end

    defp redact_ssh_key(nil), do: nil
    defp redact_ssh_key(ref) when is_binary(ref) do
      digest = :crypto.hash(:sha256, ref) |> Base.encode16(case: :lower) |> binary_part(0, 8)
      "[REDACTED:ssh_key_ref:" <> digest <> "]"
    end
  end
end

defmodule Chassis.Contracts.BEAMNode do
  @moduledoc "BEAM node placement descriptor."
  defstruct [
    :node_ref,
    :node_name,
    :physical_host_ref,
    :profile_ref,
    virtual_servers: [],
    status: :unknown
  ]

  @type t :: %__MODULE__{
          node_ref: String.t() | nil,
          node_name: atom() | nil,
          physical_host_ref: String.t() | nil,
          profile_ref: String.t() | nil,
          virtual_servers: [atom()],
          status: atom()
        }
end

defmodule Chassis.Contracts.HostProvisioningConfig do
  @moduledoc "OS + provider provisioning configuration."
  defstruct [
    :env_config_ref,
    :os,
    :provider,
    runtime_versions: %{},
    setup_script: [],
    ufw_ports: [],
    install_paths: %{}
  ]

  @type t :: %__MODULE__{
          env_config_ref: String.t() | nil,
          os: String.t() | nil,
          provider: String.t() | nil,
          runtime_versions: map(),
          setup_script: [String.t()],
          ufw_ports: [String.t()],
          install_paths: map()
        }
end

defmodule Chassis.Contracts.EnvironmentResolver do
  @moduledoc "Links ConfigurationProfile + environment to HostProvisioningConfig."
  defstruct [:profile_name, :environment, :provisioning_config_ref]

  @type t :: %__MODULE__{
          profile_name: String.t() | nil,
          environment: :dev | :prod | nil,
          provisioning_config_ref: String.t() | nil
        }
end

defmodule Chassis.Contracts.IsolationProfile do
  @moduledoc "Tenant isolation controls."
  defstruct [
    :isolation_ref,
    compute_isolation: :shared,
    data_isolation: :row,
    secrets_isolation: :shared,
    observability_isolation: :shared_redacted
  ]

  @type t :: %__MODULE__{
          isolation_ref: String.t() | nil,
          compute_isolation: atom(),
          data_isolation: atom(),
          secrets_isolation: atom(),
          observability_isolation: atom()
        }
end

defmodule Chassis.Contracts.ResidencyContract do
  @moduledoc "Allowed regions and providers for a tenant."
  defstruct [:residency_ref, allowed_regions: [], forbidden_regions: [], allowed_providers: []]

  @type t :: %__MODULE__{
          residency_ref: String.t() | nil,
          allowed_regions: [String.t()],
          forbidden_regions: [String.t()],
          allowed_providers: [String.t()]
        }
end

defmodule Chassis.Contracts.Adapter do
  @moduledoc """
  Behaviour every substrate adapter implements. The four callbacks are the
  full surface a `Chassis.Core.Dispatcher` is allowed to invoke. Adapters
  whose underlying transport is not yet active must return
  `{:error, {:not_implemented, __MODULE__}}` from every callback.
  """
  @callback prepare(map(), keyword()) :: {:ok, map()} | {:error, term()}
  @callback start(map(), keyword()) :: {:ok, map()} | {:error, term()}
  @callback stop(map(), keyword()) :: {:ok, map()} | {:error, term()}
  @callback health(map(), keyword()) :: {:ok, map()} | {:error, term()}
end

defmodule NSHKR.Tenant.TenantContext do
  @moduledoc """
  Tenant context re-exported until `nshkr_tenant_contracts` is split out.

  Includes a `defimpl Inspect` that masks the tenant_ref so deploy logs,
  Mix.shell output, and crash reports never embed the raw tenant_ref.
  """
  @enforce_keys [:tenant_ref, :installation_ref]
  defstruct [
    :tenant_ref,
    :installation_ref,
    :actor_ref,
    :authority_ref,
    :residency_ref,
    :isolation_ref,
    labels: %{}
  ]

  @type t :: %__MODULE__{
          tenant_ref: String.t(),
          installation_ref: String.t(),
          actor_ref: String.t() | nil,
          authority_ref: String.t() | nil,
          residency_ref: String.t() | nil,
          isolation_ref: String.t() | nil,
          labels: map()
        }

  defimpl Inspect do
    import Inspect.Algebra

    def inspect(ctx, opts) do
      masked = %{ctx | tenant_ref: redact(ctx.tenant_ref)}
      concat(["%NSHKR.Tenant.TenantContext{", to_doc(Map.from_struct(masked), opts), "}"])
    end

    defp redact(nil), do: nil

    defp redact(ref) when is_binary(ref) do
      if String.starts_with?(ref, "tenant:hashed:") do
        ref
      else
        digest = :crypto.hash(:sha256, ref) |> Base.encode16(case: :lower) |> binary_part(0, 8)
        "[REDACTED:tenant:" <> digest <> "]"
      end
    end
  end
end
