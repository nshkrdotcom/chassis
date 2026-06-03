defmodule Chassis.AITrace.Bridge.AttributeFilter do
  @moduledoc """
  Chassis-specific AITrace attribute filtering.

  The filter hashes raw IP values and raw BEAM node names before applying the
  sibling AITrace export bounds profile. It also drops Chassis-local sensitive
  fields that are operational implementation details rather than evidence refs.
  """

  @drop_exact ~w(ssh_user ssh_key_ref lease_material)
  @ip_keys ~w(ip ip_address host_ip public_ip private_ip)a
  @node_keys ~w(node_name beam_node node_ref)a

  @type surface :: :trace_metadata | :span_attributes | :event_attributes

  @spec filter(map(), surface()) :: map()
  def filter(attrs, surface \\ :span_attributes) when is_map(attrs) do
    attrs
    |> normalize_keys()
    |> drop_chassis_sensitive()
    |> redact_ip_addresses()
    |> redact_node_names()
    |> AITrace.ExportBounds.bound_map!(surface: surface)
  end

  @spec export_bounds_profile() :: map()
  def export_bounds_profile, do: AITrace.ExportBounds.profile()

  defp normalize_keys(attrs) do
    Map.new(attrs, fn {key, value} -> {normalize_key(key), value} end)
  end

  defp normalize_key(key) when is_atom(key), do: Atom.to_string(key)
  defp normalize_key(key), do: to_string(key)

  defp drop_chassis_sensitive(attrs) do
    Map.reject(attrs, fn {key, _value} ->
      key in @drop_exact
    end)
  end

  defp redact_ip_addresses(attrs) do
    Enum.reduce(@ip_keys, attrs, fn key, acc ->
      key = Atom.to_string(key)

      case Map.fetch(acc, key) do
        {:ok, value} when is_binary(value) -> Map.put(acc, key, "ip:" <> digest(value))
        {:ok, value} -> Map.put(acc, key, "ip:" <> digest(inspect(value)))
        :error -> acc
      end
    end)
  end

  defp redact_node_names(attrs) do
    Enum.reduce(@node_keys, attrs, fn key, acc ->
      key = Atom.to_string(key)

      case Map.fetch(acc, key) do
        {:ok, value} when is_atom(value) ->
          Map.put(acc, key, "node:" <> digest(Atom.to_string(value)))

        {:ok, value} when is_binary(value) ->
          if raw_node_name?(key, value) do
            Map.put(acc, key, "node:" <> digest(value))
          else
            acc
          end

        {:ok, value} ->
          Map.put(acc, key, "node:" <> digest(inspect(value)))

        :error ->
          acc
      end
    end)
  end

  defp raw_node_name?("node_name", value), do: value != ""
  defp raw_node_name?("beam_node", value), do: value != ""
  defp raw_node_name?("node_ref", value), do: String.contains?(value, "@")

  defp digest(value) do
    :crypto.hash(:sha256, value)
    |> Base.encode16(case: :lower)
    |> binary_part(0, 16)
  end
end
