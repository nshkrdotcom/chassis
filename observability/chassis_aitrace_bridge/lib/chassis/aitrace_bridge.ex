defmodule Chassis.AITrace.Bridge do
  @moduledoc "AITrace bridge applying bounded attributes."
  @spec emit_span(String.t(), map(), keyword()) :: {:ok, map()}
  def emit_span(name, attrs, opts \\ []), do: emit(:span, name, attrs, opts)
  @spec emit_event(String.t(), map(), keyword()) :: {:ok, map()}
  def emit_event(name, attrs, opts \\ []), do: emit(:event, name, attrs, opts)

  defp emit(kind, name, attrs, _opts),
    do:
      {:ok,
       %{kind: kind, name: name, attrs: Chassis.AITrace.Bridge.AttributeFilter.filter(attrs)}}
end

defmodule Chassis.AITrace.Bridge.AttributeFilter do
  @moduledoc "Chassis-specific redaction."
  @blocked ~w(ip node_name private_key secret password token)
  @spec filter(map()) :: map()
  def filter(attrs),
    do:
      Map.new(attrs, fn {key, value} ->
        if Enum.any?(@blocked, &String.contains?(String.downcase(to_string(key)), &1)),
          do: {key, hash(value)},
          else: {key, value}
      end)

  defp hash(value),
    do: "sha256:" <> (:crypto.hash(:sha256, inspect(value)) |> Base.encode16(case: :lower))
end

defmodule Chassis.AITrace.Bridge.TestEmitter do
  @moduledoc "Test emitter."
  def spans, do: []
end
