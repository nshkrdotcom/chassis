defmodule Chassis.AITrace.Bridge.Exporter.JSONL do
  @moduledoc """
  AITrace exporter that writes Chassis span/event records as JSONL.

  This exporter exists for Chassis CLI smoke tests and local development where
  operators pass `file:///...jsonl` and then grep for span names. It still
  receives completed `AITrace.Trace` values from the normal AITrace exporter
  pipeline.
  """

  @behaviour AITrace.Exporter

  alias AITrace.{Event, Span, Trace}

  @schema_version "chassis.aitrace_bridge.jsonl.v1"

  @impl true
  def init(opts) when is_list(opts), do: init(Map.new(opts))

  def init(opts) when is_map(opts) do
    path = Map.get(opts, :path, Map.get(opts, "path"))

    if is_binary(path) and path != "" do
      {:ok, %{path: path}}
    else
      {:error, :missing_jsonl_path}
    end
  end

  @impl true
  def export(%Trace{} = trace, %{path: path} = state) do
    trace.spans
    |> Enum.flat_map(&span_records(trace, &1))
    |> Enum.reduce_while(:ok, fn record, :ok ->
      case AITrace.JSONL.append(path, record) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      :ok -> {:ok, Map.put(state, :last_record_count, record_count(trace))}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def shutdown(_state), do: :ok

  defp span_records(%Trace{} = trace, %Span{} = span) do
    [span_record(trace, span) | Enum.map(span.events, &event_record(trace, span, &1))]
  end

  defp span_record(%Trace{} = trace, %Span{} = span) do
    %{
      schema_version: @schema_version,
      kind: "span",
      name: span.name,
      trace_id: trace.trace_id,
      span_id: span.span_id,
      parent_span_id: span.parent_span_id,
      status: Atom.to_string(span.status),
      attributes: span.attributes,
      metadata: trace.metadata,
      export_bounds: AITrace.ExportBounds.profile(),
      timestamp: timestamp()
    }
  end

  defp event_record(%Trace{} = trace, %Span{} = span, %Event{} = event) do
    %{
      schema_version: @schema_version,
      kind: "event",
      name: event.name,
      trace_id: trace.trace_id,
      span_id: span.span_id,
      parent_span_name: span.name,
      attributes: event.attributes,
      metadata: trace.metadata,
      export_bounds: AITrace.ExportBounds.profile(),
      timestamp: timestamp()
    }
  end

  defp record_count(%Trace{} = trace) do
    Enum.reduce(trace.spans, 0, fn span, count -> count + 1 + length(span.events) end)
  end

  defp timestamp, do: DateTime.utc_now() |> DateTime.to_iso8601()
end
