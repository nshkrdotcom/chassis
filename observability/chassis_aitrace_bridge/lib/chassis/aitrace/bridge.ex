defmodule Chassis.AITrace.Bridge do
  @moduledoc """
  Emits Chassis spans and events through AITrace with bounded attributes.

  The bridge always builds completed `AITrace.Trace` values and exports them
  through configured AITrace exporters. Attributes pass through
  `Chassis.AITrace.Bridge.AttributeFilter`, which applies Chassis-specific
  hashing before delegating to `AITrace.ExportBounds`.
  """

  alias AITrace.{Event, Span, Trace}
  alias Chassis.AITrace.Bridge.AttributeFilter

  @span_catalogue %{
    "chassis.deployment.accepted" => %{
      required: [:tenant_ref, :installation_ref, :app_atom, :profile_ref, :environment, :git_sha],
      optional: [:release_version],
      source: "Chassis.Mezzanine.Bridge.MaterializeDeployment.call/2"
    },
    "chassis.adapter.selected" => %{
      required: [
        :profile_ref,
        :environment,
        :provisioning_adapter,
        :mesh_adapter,
        :secrets_materializer
      ],
      optional: [],
      source: "Chassis.Stack.ProfileResolver.resolve/2"
    },
    "chassis.provisioning.started" => %{
      required: [:host_ref, :env_config_ref, :phase],
      optional: [],
      source: "Chassis.Provisioning.SSHBootstrap.prepare_host/3"
    },
    "chassis.provisioning.completed" => %{
      required: [:host_ref, :phase, :status, :step_count],
      optional: [:duration_ms],
      source: "Chassis.Receipts.ProvisioningRecord.after_action"
    },
    "chassis.mesh.joined" => %{
      required: [:node_ref, :cluster_ref],
      optional: [:cipher_suite],
      source: "Chassis.Mesh.BEAMDistribution.init_node/1"
    },
    "chassis.health.checked" => %{
      required: [:node_ref, :status],
      optional: [:latency_ms, :reason],
      source: "Chassis.Mesh.HealthSupervisor.tick/0"
    },
    "chassis.health.unhealthy" => %{
      required: [:node_ref, :status, :reason],
      optional: [:observed_value, :threshold, :unit],
      source: "Chassis.Mesh.HealthSupervisor"
    },
    "chassis.receipt.emitted" => %{
      required: [:receipt_ref, :tenant_ref, :app_atom, :status],
      optional: [],
      source: "Chassis.Receipts.DeploymentRecord.after_action"
    },
    "chassis.rollback.triggered" => %{
      required: [:previous_receipt_ref, :trigger, :tenant_ref],
      optional: [:app_atom, :actor_ref],
      source: "Chassis.StackManager.rollback/2"
    },
    "chassis.deployment.denied" => %{
      required: [:tenant_ref, :installation_ref, :protocol_ref, :code],
      optional: [:safe_message],
      source: "Chassis.Policy.Boundary.authorize/1"
    },
    "chassis.secret.materialized" => %{
      required: [:secret_ref, :backend, :consumer_ref],
      optional: [:lease_ref],
      source: "Chassis.Secrets.Materializer.*.materialize/2"
    },
    "chassis.secret.revoked" => %{
      required: [:lease_ref, :consumer_ref],
      optional: [],
      source: "Chassis.Secrets.LeaseSupervisor"
    },
    "chassis.key.rotated" => %{
      required: [:key_name, :previous_version, :new_version],
      optional: [:fingerprint],
      source: "Chassis.Keys.Manager.rotate/2"
    }
  }

  @type span_name :: String.t()
  @type attributes :: map() | keyword()
  @type emit_opts :: keyword()
  @type exported_ref :: String.t()

  @spec emit_span(span_name(), attributes(), emit_opts()) ::
          {:ok, exported_ref()} | {:error, term()}
  def emit_span(name, attributes, opts \\ []) do
    with {:ok, attrs} <- normalize_attrs(attributes),
         {:ok, spec} <- span_spec(name),
         :ok <- validate_required(attrs, spec.required),
         {:ok, trace_id} <- trace_id(opts),
         {:ok, status} <- status(opts),
         {:ok, exporters} <- configured_exporters(opts) do
      span =
        name
        |> new_span(Keyword.get(opts, :parent_span_id))
        |> Span.with_attributes(AttributeFilter.filter(attrs, :span_attributes))
        |> Span.with_status(status)
        |> Span.finish()

      trace =
        trace_id
        |> Trace.new(id_source: :external_alias)
        |> Trace.with_metadata(trace_metadata(:span, name, spec, opts))
        |> Trace.add_span(span)

      case AITrace.export(trace, exporters) do
        :ok -> {:ok, "span:" <> span.span_id}
        {:error, reason} -> {:error, {:export_failed, reason}}
      end
    end
  end

  @spec emit_event(span_name(), attributes(), emit_opts()) ::
          {:ok, exported_ref()} | {:error, term()}
  def emit_event(name, attributes, opts \\ []) do
    with {:ok, attrs} <- normalize_attrs(attributes),
         {:ok, spec} <- span_spec(name),
         :ok <- validate_required(attrs, spec.required),
         {:ok, trace_id} <- trace_id(opts),
         {:ok, status} <- status(opts),
         {:ok, exporters} <- configured_exporters(opts) do
      event = Event.new(name, AttributeFilter.filter(attrs, :event_attributes))

      span =
        "chassis.aitrace.event"
        |> new_span(Keyword.get(opts, :parent_span_id))
        |> Span.add_event(event)
        |> Span.with_status(status)
        |> Span.finish()

      trace =
        trace_id
        |> Trace.new(id_source: :external_alias)
        |> Trace.with_metadata(trace_metadata(:event, name, spec, opts))
        |> Trace.add_span(span)

      case AITrace.export(trace, exporters) do
        :ok -> {:ok, "event:" <> event_ref(trace_id, span.span_id, name, event.attributes)}
        {:error, reason} -> {:error, {:export_failed, reason}}
      end
    end
  end

  @spec span_names() :: [String.t()]
  def span_names, do: @span_catalogue |> Map.keys() |> Enum.sort()

  @spec catalogue() :: map()
  def catalogue, do: @span_catalogue

  @spec required_attributes(span_name()) :: [atom()]
  def required_attributes(name) do
    case span_spec(name) do
      {:ok, spec} -> spec.required
      {:error, _reason} -> []
    end
  end

  @spec span_spec(span_name()) :: {:ok, map()} | {:error, term()}
  def span_spec(name) when is_binary(name) do
    case Map.fetch(@span_catalogue, name) do
      {:ok, spec} -> {:ok, spec}
      :error -> {:error, {:unknown_span_name, name}}
    end
  end

  def span_spec(other), do: {:error, {:invalid_span_name, other}}

  @spec validate_required(map(), [atom()]) :: :ok | {:error, term()}
  def validate_required(attrs, required) when is_map(attrs) and is_list(required) do
    missing =
      required
      |> Enum.reject(&present_attribute?(attrs, &1))
      |> Enum.map(&Atom.to_string/1)

    if missing == [] do
      :ok
    else
      {:error, {:missing_required_attributes, missing}}
    end
  end

  @spec file_exporter_from_url(String.t()) :: {:ok, list()} | {:error, term()}
  def file_exporter_from_url("file://" <> path) when path != "" do
    {:ok, [{Chassis.AITrace.Bridge.Exporter.JSONL, path: path}]}
  end

  def file_exporter_from_url(url), do: {:error, {:unsupported_export_url, url}}

  @spec default_exporters(atom()) :: list()
  def default_exporters(env \\ Application.get_env(:chassis_aitrace_bridge, :runtime_env, :dev))

  def default_exporters(:prod) do
    Application.get_env(:chassis_aitrace_bridge, :otel_exporters, [])
  end

  def default_exporters(_env) do
    [{AITrace.Exporter.File, directory: "/tmp/chassis_aitrace"}]
  end

  defp configured_exporters(opts) do
    cond do
      Keyword.has_key?(opts, :exporters) ->
        normalize_exporters(Keyword.fetch!(opts, :exporters))

      Keyword.has_key?(opts, :export_url) ->
        file_exporter_from_url(Keyword.fetch!(opts, :export_url))

      true ->
        exporters =
          Application.get_env(:chassis_aitrace_bridge, :exporters) ||
            Application.get_env(:aitrace, :exporters) ||
            default_exporters()

        normalize_exporters(exporters)
    end
  end

  defp normalize_exporters(exporters) when is_list(exporters), do: {:ok, exporters}
  defp normalize_exporters(other), do: {:error, {:invalid_exporters, other}}

  defp normalize_attrs(attrs) when is_map(attrs), do: {:ok, attrs}

  defp normalize_attrs(attrs) when is_list(attrs) do
    if Keyword.keyword?(attrs) do
      {:ok, Map.new(attrs)}
    else
      {:error, :invalid_attributes}
    end
  end

  defp normalize_attrs(_attrs), do: {:error, :invalid_attributes}

  defp present_attribute?(attrs, key) do
    value = Map.get(attrs, key, Map.get(attrs, Atom.to_string(key)))
    not missing?(value)
  end

  defp missing?(nil), do: true
  defp missing?(""), do: true
  defp missing?([]), do: true
  defp missing?(_value), do: false

  defp trace_id(opts) do
    case Keyword.get(opts, :trace_id) do
      nil -> {:ok, "trace:" <> AITrace.Identifier.generate(:trace)}
      value when is_binary(value) and value != "" -> {:ok, value}
      other -> {:error, {:invalid_trace_id, other}}
    end
  end

  defp status(opts) do
    case Keyword.get(opts, :status, :ok) do
      value when value in [:ok, :error] -> {:ok, value}
      other -> {:error, {:invalid_status, other}}
    end
  end

  defp new_span(name, nil), do: Span.new(name)

  defp new_span(name, parent_span_id) when is_binary(parent_span_id),
    do: Span.new(name, parent_span_id)

  defp new_span(_name, parent_span_id),
    do: raise(ArgumentError, "parent_span_id must be a binary, got: #{inspect(parent_span_id)}")

  defp trace_metadata(kind, name, spec, opts) do
    %{
      "component_ref" => "component:chassis",
      "plane_ref" => "plane:data:aitrace",
      "chassis_span_name" => name,
      "chassis_span_kind" => Atom.to_string(kind),
      "chassis_span_source" => spec.source,
      "export_bounds_profile" => AITrace.ExportBounds.profile().schema_version,
      "correlation_id" => Keyword.get(opts, :correlation_id)
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
    |> AITrace.ExportBounds.bound_map!(surface: :trace_metadata)
  end

  defp event_ref(trace_id, span_id, name, attributes) do
    :crypto.hash(:sha256, :erlang.term_to_binary({trace_id, span_id, name, attributes}))
    |> Base.encode16(case: :lower)
    |> binary_part(0, 24)
  end
end
