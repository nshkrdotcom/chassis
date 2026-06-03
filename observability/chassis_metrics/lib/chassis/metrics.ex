defmodule NSHKR.Observability.Emitter do
  @moduledoc "Observability emitter behaviour used by Chassis."

  alias NSHKR.Observability.{HealthSignal, Metric, StructuredLog}

  @callback emit(Metric.t() | HealthSignal.t() | StructuredLog.t(), keyword()) ::
              :ok | {:error, term()}
  @callback emit_metric(map()) :: :ok | {:error, term()}
  @callback emit_health_signal(map()) :: :ok | {:error, term()}
end

defmodule NSHKR.Observability.Metric do
  @moduledoc "OTel-compatible metric payload."

  @enforce_keys [:metric_ref, :name, :kind, :value, :unit, :labels, :timestamp]
  defstruct [:metric_ref, :name, :kind, :value, :unit, :labels, :timestamp, :trace_id]

  @type kind :: :counter | :gauge | :histogram

  @type t :: %__MODULE__{
          metric_ref: String.t(),
          name: String.t(),
          kind: kind(),
          value: number(),
          unit: atom(),
          labels: map(),
          timestamp: DateTime.t(),
          trace_id: String.t() | nil
        }
end

defmodule NSHKR.Observability.HealthSignal do
  @moduledoc "Operational health signal emitted by the metabolic plane."

  @enforce_keys [:signal_ref, :component_ref, :service_ref, :status, :timestamp]
  defstruct [
    :signal_ref,
    :component_ref,
    :service_ref,
    :status,
    :reason,
    :observed_value,
    :threshold,
    :unit,
    :trace_id,
    :timestamp,
    metadata: %{}
  ]

  @type t :: %__MODULE__{
          signal_ref: String.t(),
          component_ref: String.t(),
          service_ref: String.t(),
          status: atom() | String.t(),
          reason: atom() | String.t() | nil,
          observed_value: number() | nil,
          threshold: number() | nil,
          unit: atom() | String.t() | nil,
          trace_id: String.t() | nil,
          timestamp: DateTime.t(),
          metadata: map()
        }
end

defmodule NSHKR.Observability.StructuredLog do
  @moduledoc "Structured observability log payload."

  @enforce_keys [:log_ref, :level, :event, :labels, :timestamp]
  defstruct [:log_ref, :level, :event, :labels, :timestamp, :trace_id]

  @type t :: %__MODULE__{
          log_ref: String.t(),
          level: atom(),
          event: String.t(),
          labels: map(),
          timestamp: DateTime.t(),
          trace_id: String.t() | nil
        }
end

defmodule Chassis.Metrics do
  @moduledoc """
  OTel-compatible metrics and health-signal bridge for Chassis.

  Metrics are validated against the Phase 15 catalogue before they are emitted.
  Tenant labels are partitioned according to
  `Chassis.Contracts.IsolationProfile.observability_isolation`.
  """

  @behaviour NSHKR.Observability.Emitter

  alias Chassis.Contracts.IsolationProfile
  alias NSHKR.Observability.{HealthSignal, Metric, StructuredLog}

  @metric_catalogue %{
    chassis_deployment_count_total: %{
      name: "chassis.deployment.count_total",
      kind: :counter,
      unit: :count,
      labels: [:profile, :env, :status, :tenant_ref]
    },
    chassis_deployment_duration_ms: %{
      name: "chassis.deployment.duration_ms",
      kind: :histogram,
      unit: :milliseconds,
      labels: [:profile, :env]
    },
    chassis_provisioning_step_count: %{
      name: "chassis.provisioning.step_count",
      kind: :gauge,
      unit: :count,
      labels: [:phase, :status]
    },
    chassis_ssh_session_duration_ms: %{
      name: "chassis.ssh.session_duration_ms",
      kind: :histogram,
      unit: :milliseconds,
      labels: [:host_ref]
    },
    chassis_mesh_node_count: %{
      name: "chassis.mesh.node_count",
      kind: :gauge,
      unit: :count,
      labels: [:cluster_ref]
    },
    chassis_mesh_health_failures_total: %{
      name: "chassis.mesh.health_failures_total",
      kind: :counter,
      unit: :count,
      labels: [:node_ref, :reason]
    },
    chassis_secret_lease_count: %{
      name: "chassis.secret.lease_count",
      kind: :gauge,
      unit: :count,
      labels: [:backend]
    },
    chassis_secret_lease_expiry_total: %{
      name: "chassis.secret.lease_expiry_total",
      kind: :counter,
      unit: :count,
      labels: [:backend, :reason]
    },
    chassis_rollback_count_total: %{
      name: "chassis.rollback.count_total",
      kind: :counter,
      unit: :count,
      labels: [:trigger, :tenant_ref]
    },
    chassis_authority_denied_total: %{
      name: "chassis.authority.denied_total",
      kind: :counter,
      unit: :count,
      labels: [:operation, :tenant_ref]
    },
    chassis_boundary_call_duration_ms: %{
      name: "chassis.boundary.call_duration_ms",
      kind: :histogram,
      unit: :milliseconds,
      labels: [:protocol_ref, :adapter, :status]
    },
    chassis_topology_validation_failures_total: %{
      name: "chassis.topology.validation_failures_total",
      kind: :counter,
      unit: :count,
      labels: [:tenant_ref, :error_code]
    }
  }

  @health_required [:service_ref, :status]

  @impl true
  def emit(%Metric{} = metric, opts), do: dispatch(metric, opts)

  def emit(%StructuredLog{} = log, opts), do: dispatch(log, opts)

  def emit(%HealthSignal{} = signal, opts), do: dispatch(signal, opts)

  @impl true
  def emit_metric(attrs) when is_map(attrs) do
    with {:ok, metric_atom} <- fetch_metric_atom(attrs),
         {:ok, value} <- fetch_metric_value(attrs) do
      emit_metric_by_kind(
        metric_atom,
        value,
        Map.get(attrs, :labels, %{}),
        Map.get(attrs, :opts, [])
      )
    end
  end

  @spec incr(atom(), map() | keyword(), keyword()) :: :ok | {:error, term()}
  def incr(metric_atom, labels \\ %{}, opts \\ []) do
    build_metric(metric_atom, :counter, 1, labels, opts)
    |> emit_built(opts)
  end

  @spec observe(atom(), number(), map() | keyword(), keyword()) :: :ok | {:error, term()}
  def observe(metric_atom, value, labels \\ %{}, opts \\ []) when is_number(value) do
    build_metric(metric_atom, :histogram, value, labels, opts)
    |> emit_built(opts)
  end

  @spec gauge(atom(), number(), map() | keyword(), keyword()) :: :ok | {:error, term()}
  def gauge(metric_atom, value, labels \\ %{}, opts \\ []) when is_number(value) do
    build_metric(metric_atom, :gauge, value, labels, opts)
    |> emit_built(opts)
  end

  @impl true
  def emit_health_signal(attrs) when is_map(attrs) do
    emit_health_signal(attrs, [])
  end

  @spec emit_health_signal(map(), keyword()) :: :ok | {:error, term()}
  def emit_health_signal(attrs, opts) when is_map(attrs) and is_list(opts) do
    with :ok <- validate_health_required(attrs) do
      %HealthSignal{
        signal_ref: Map.get(attrs, :signal_ref, "health-signal:" <> short_id()),
        component_ref: Map.get(attrs, :component_ref, "component:chassis"),
        service_ref: Map.fetch!(attrs, :service_ref),
        status: Map.fetch!(attrs, :status),
        reason: Map.get(attrs, :reason),
        observed_value: Map.get(attrs, :observed_value),
        threshold: Map.get(attrs, :threshold),
        unit: Map.get(attrs, :unit),
        trace_id: Map.get(attrs, :trace_id, "trace:" <> short_id()),
        timestamp: Map.get(attrs, :timestamp, DateTime.utc_now()),
        metadata: Map.get(attrs, :metadata, %{})
      }
      |> emit(opts)
    end
  end

  @spec metric_catalogue() :: map()
  def metric_catalogue, do: @metric_catalogue

  @spec metric_names() :: [String.t()]
  def metric_names do
    @metric_catalogue
    |> Map.values()
    |> Enum.map(& &1.name)
    |> Enum.sort()
  end

  @spec metric_spec(atom()) :: map() | nil
  def metric_spec(metric_atom), do: Map.get(@metric_catalogue, metric_atom)

  @spec label_partition(map() | keyword(), keyword()) :: map()
  def label_partition(labels, opts \\ []) do
    isolation =
      opts
      |> Keyword.get(:isolation_profile, %IsolationProfile{})
      |> observability_isolation()

    labels
    |> stringify_labels()
    |> partition_tenant_ref(isolation)
  end

  defp build_metric(metric_atom, requested_kind, value, labels, opts) do
    with {:ok, spec} <- fetch_spec(metric_atom),
         :ok <- require_kind(spec.kind, requested_kind),
         {:ok, normalized_labels} <- validate_labels(labels, spec.labels, opts) do
      {:ok,
       %Metric{
         metric_ref: "metric:" <> spec.name <> ":" <> short_id(),
         name: spec.name,
         kind: spec.kind,
         value: value,
         unit: spec.unit,
         labels: normalized_labels,
         timestamp: DateTime.utc_now(),
         trace_id: Keyword.get(opts, :trace_id)
       }}
    end
  end

  defp emit_built({:ok, %Metric{} = metric}, opts), do: emit(metric, opts)
  defp emit_built({:error, reason}, _opts), do: {:error, reason}

  defp emit_metric_by_kind(metric_atom, value, labels, opts) do
    with {:ok, spec} <- fetch_spec(metric_atom) do
      case spec.kind do
        :counter -> incr(metric_atom, labels, opts)
        :gauge -> gauge(metric_atom, value, labels, opts)
        :histogram -> observe(metric_atom, value, labels, opts)
      end
    end
  end

  defp fetch_metric_atom(%{metric_atom: metric_atom}) when is_atom(metric_atom),
    do: {:ok, metric_atom}

  defp fetch_metric_atom(%{name: metric_atom}) when is_atom(metric_atom), do: {:ok, metric_atom}
  defp fetch_metric_atom(_attrs), do: {:error, :missing_metric_atom}

  defp fetch_metric_value(%{value: value}) when is_number(value), do: {:ok, value}
  defp fetch_metric_value(_attrs), do: {:error, :missing_metric_value}

  defp fetch_spec(metric_atom) do
    case Map.fetch(@metric_catalogue, metric_atom) do
      {:ok, spec} -> {:ok, spec}
      :error -> {:error, {:unknown_metric, metric_atom}}
    end
  end

  defp require_kind(kind, kind), do: :ok
  defp require_kind(actual, requested), do: {:error, {:wrong_metric_kind, actual, requested}}

  defp validate_labels(labels, required, opts) do
    normalized = label_partition(labels, opts)

    missing =
      required
      |> Enum.map(&Atom.to_string/1)
      |> Enum.reject(fn key -> present?(Map.get(normalized, key)) end)

    if missing == [] do
      {:ok, normalized}
    else
      {:error, {:missing_metric_labels, missing}}
    end
  end

  defp stringify_labels(labels) when is_map(labels) do
    Map.new(labels, fn {key, value} -> {to_string(key), to_string(value)} end)
  end

  defp stringify_labels(labels) when is_list(labels) do
    if Keyword.keyword?(labels) do
      labels |> Map.new() |> stringify_labels()
    else
      %{}
    end
  end

  defp stringify_labels(_labels), do: %{}

  defp partition_tenant_ref(labels, isolation) do
    labels
    |> maybe_partition_tenant_ref(isolation)
    |> Map.put_new("tenant_partition", Atom.to_string(isolation))
  end

  defp maybe_partition_tenant_ref(%{"tenant_ref" => tenant_ref} = labels, isolation)
       when isolation in [:shared_redacted, :shared, :redacted] do
    Map.put(labels, "tenant_ref", "tenant:sha256:" <> digest(tenant_ref))
  end

  defp maybe_partition_tenant_ref(labels, _isolation), do: labels

  defp observability_isolation(%IsolationProfile{observability_isolation: isolation}),
    do: isolation

  defp observability_isolation(%{observability_isolation: isolation}) when is_atom(isolation),
    do: isolation

  defp observability_isolation(_profile), do: :shared_redacted

  defp validate_health_required(attrs) do
    case Enum.find(@health_required, &(not present?(Map.get(attrs, &1)))) do
      nil -> :ok
      missing -> {:error, {:missing_required_health_signal_attr, missing}}
    end
  end

  defp dispatch(signal, opts) do
    with {:ok, module, backend_opts} <- normalize_backend(Keyword.get(opts, :backend)) do
      module.emit(signal, Keyword.merge(opts, backend_opts))
    end
  end

  defp normalize_backend(nil) do
    normalize_backend(
      Application.get_env(:chassis_metrics, :backend, Chassis.Metrics.Backend.OTel)
    )
  end

  defp normalize_backend(module) when is_atom(module), do: {:ok, module, []}

  defp normalize_backend({module, opts}) when is_atom(module) and is_list(opts),
    do: {:ok, module, opts}

  defp normalize_backend({module, opts}) when is_atom(module) and is_map(opts),
    do: {:ok, module, Map.to_list(opts)}

  defp normalize_backend(other), do: {:error, {:invalid_backend, other}}

  defp present?(nil), do: false
  defp present?(""), do: false
  defp present?(_value), do: true

  defp short_id do
    8
    |> :crypto.strong_rand_bytes()
    |> Base.encode16(case: :lower)
  end

  defp digest(value) do
    :crypto.hash(:sha256, value)
    |> Base.encode16(case: :lower)
    |> binary_part(0, 16)
  end
end

defmodule Chassis.Metrics.Backend.Test do
  @moduledoc "In-memory ETS metrics backend for tests."

  @table :chassis_metrics_test

  @spec emit(term(), keyword()) :: :ok
  def emit(signal, _opts \\ []) do
    ensure_table()
    :ets.insert(@table, {System.unique_integer([:positive, :monotonic]), signal})
    :ok
  end

  @spec reset() :: :ok
  def reset do
    ensure_table()
    :ets.delete_all_objects(@table)
    :ok
  end

  @spec list() :: [term()]
  def list do
    ensure_table()

    @table
    |> :ets.tab2list()
    |> Enum.sort_by(fn {key, _signal} -> key end)
    |> Enum.map(fn {_key, signal} -> signal end)
  end

  defp ensure_table do
    case :ets.whereis(@table) do
      :undefined -> :ets.new(@table, [:named_table, :public, :ordered_set])
      tid -> tid
    end
  end
end

defmodule Chassis.Metrics.Backend.File do
  @moduledoc "JSONL metrics backend."

  alias NSHKR.Observability.{HealthSignal, Metric, StructuredLog}

  @default_path "/opt/nshkr/metrics/chassis.jsonl"

  @spec emit(Metric.t() | HealthSignal.t() | StructuredLog.t(), keyword()) ::
          :ok | {:error, term()}
  def emit(signal, opts \\ []) do
    path =
      Keyword.get(opts, :path, Application.get_env(:chassis_metrics, :file_path, @default_path))

    with :ok <- File.mkdir_p(Path.dirname(path)),
         {:ok, line} <- Jason.encode(normalize(signal)) do
      File.write(path, line <> "\n", [:append])
    end
  end

  defp normalize(%Metric{} = metric) do
    %{
      schema_version: "chassis.metrics.metric.v1",
      kind: Atom.to_string(metric.kind),
      metric_ref: metric.metric_ref,
      name: metric.name,
      value: metric.value,
      unit: Atom.to_string(metric.unit),
      labels: metric.labels,
      trace_id: metric.trace_id,
      timestamp: DateTime.to_iso8601(metric.timestamp)
    }
  end

  defp normalize(%HealthSignal{} = signal) do
    %{
      schema_version: "chassis.metrics.health_signal.v1",
      kind: "health_signal",
      signal_ref: signal.signal_ref,
      component_ref: signal.component_ref,
      service_ref: signal.service_ref,
      status: to_string(signal.status),
      reason: to_string(signal.reason || "unknown"),
      observed_value: signal.observed_value,
      threshold: signal.threshold,
      unit: to_string(signal.unit || "unknown"),
      trace_id: signal.trace_id,
      metadata: signal.metadata,
      timestamp: DateTime.to_iso8601(signal.timestamp)
    }
  end

  defp normalize(%StructuredLog{} = log) do
    %{
      schema_version: "chassis.metrics.structured_log.v1",
      kind: "structured_log",
      log_ref: log.log_ref,
      level: Atom.to_string(log.level),
      event: log.event,
      labels: log.labels,
      trace_id: log.trace_id,
      timestamp: DateTime.to_iso8601(log.timestamp)
    }
  end
end

defmodule Chassis.Metrics.Backend.Console do
  @moduledoc "Console metrics backend for local debugging."

  @spec emit(term(), keyword()) :: :ok
  def emit(signal, _opts \\ []) do
    IO.inspect(signal, label: "chassis.metrics")
    :ok
  end
end

defmodule Chassis.Metrics.Backend.OTel do
  @moduledoc "OpenTelemetry-compatible backend using Erlang telemetry events."

  alias NSHKR.Observability.{HealthSignal, Metric, StructuredLog}

  @spec emit(Metric.t() | HealthSignal.t() | StructuredLog.t(), keyword()) :: :ok
  def emit(signal, opts \\ [])

  def emit(%Metric{} = metric, _opts) do
    :telemetry.execute(
      [:chassis, :metrics, :metric],
      %{value: metric.value},
      %{
        metric_ref: metric.metric_ref,
        name: metric.name,
        kind: metric.kind,
        unit: metric.unit,
        labels: metric.labels,
        trace_id: metric.trace_id
      }
    )
  end

  def emit(%HealthSignal{} = signal, _opts) do
    :telemetry.execute(
      [:chassis, :metrics, :health_signal],
      %{observed_value: signal.observed_value || 0},
      %{
        signal_ref: signal.signal_ref,
        component_ref: signal.component_ref,
        service_ref: signal.service_ref,
        status: signal.status,
        reason: signal.reason,
        threshold: signal.threshold,
        unit: signal.unit,
        trace_id: signal.trace_id
      }
    )
  end

  def emit(%StructuredLog{} = log, _opts) do
    :telemetry.execute(
      [:chassis, :metrics, :structured_log],
      %{count: 1},
      %{
        log_ref: log.log_ref,
        level: log.level,
        event: log.event,
        labels: log.labels,
        trace_id: log.trace_id
      }
    )
  end
end
