defmodule Chassis.AppKit.Surface.Error do
  @moduledoc "Product-safe AppKit spatial surface error."

  @derive {Inspect, only: [:code, :safe_message, :details]}
  defstruct [:code, :safe_message, details: %{}]

  @type t :: %__MODULE__{code: atom(), safe_message: String.t(), details: map()}
end

defmodule Chassis.AppKit.Surface do
  @moduledoc "Chassis-side schema package for AppKit spatial gateway readback."

  alias Chassis.AppKit.Surface.Error

  @type request :: struct() | map()
  @type response :: term()

  @callback handle(request(), keyword()) :: {:ok, response()} | {:error, term()}

  @spec error(atom(), String.t(), map()) :: Error.t()
  def error(code, safe_message, details \\ %{}) do
    %Error{code: code, safe_message: safe_message, details: details}
  end
end

defmodule Chassis.AppKit.Surface.Projection do
  @moduledoc "Product-safe spatial deployment projection for AppKit consumers."

  alias Chassis.AppKit.Surface

  @health_statuses MapSet.new([
                     :healthy,
                     :degraded,
                     :unhealthy,
                     "healthy",
                     "degraded",
                     "unhealthy"
                   ])
  @statuses MapSet.new([
              :active,
              :inactive,
              :failed,
              :pending,
              "active",
              "inactive",
              "failed",
              "pending"
            ])
  @fields [
    :deployment_ref,
    :app_ref,
    :app_atom,
    :tenant_ref,
    :installation_ref,
    :active_profile,
    :health_status,
    :receipt_ref,
    :status,
    :updated_at,
    :safe_labels
  ]

  @enforce_keys [:active_profile]
  defstruct [
    :deployment_ref,
    :app_ref,
    :app_atom,
    :tenant_ref,
    :installation_ref,
    :active_profile,
    :health_status,
    :receipt_ref,
    :status,
    :updated_at,
    safe_labels: %{}
  ]

  @type t :: %__MODULE__{
          deployment_ref: String.t() | nil,
          app_ref: String.t() | nil,
          app_atom: atom() | nil,
          tenant_ref: String.t() | nil,
          installation_ref: String.t() | nil,
          active_profile: String.t() | nil,
          health_status: atom() | String.t() | nil,
          receipt_ref: String.t() | nil,
          status: atom() | String.t() | nil,
          updated_at: DateTime.t() | String.t() | nil,
          safe_labels: map()
        }

  @spec new(map() | keyword()) :: {:ok, t()} | {:error, Surface.Error.t()}
  def new(attrs) when is_map(attrs) or is_list(attrs) do
    attrs = attrs |> Map.new() |> normalize_keys()

    with :ok <- require_string(attrs, :active_profile),
         :ok <- validate_enum(attrs, :health_status, @health_statuses),
         :ok <- validate_enum(attrs, :status, @statuses),
         :ok <- validate_atom(attrs, :app_atom),
         :ok <- validate_labels(attrs) do
      {:ok, struct(__MODULE__, Map.take(attrs, fields()))}
    end
  end

  @spec new!(map() | keyword()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, projection} -> projection
      {:error, error} -> raise ArgumentError, message: error.safe_message
    end
  end

  defp normalize_keys(attrs) do
    Map.new(attrs, fn {key, value} -> {normalize_key(key), value} end)
  end

  defp normalize_key(key) when is_atom(key), do: key

  defp normalize_key(key) when is_binary(key) do
    Enum.find(fields(), &(Atom.to_string(&1) == key)) || key
  end

  defp normalize_key(key), do: key

  defp require_string(attrs, key) do
    case Map.get(attrs, key) do
      value when is_binary(value) and value != "" -> :ok
      _ -> invalid("#{key} is required")
    end
  end

  defp validate_enum(attrs, key, allowed) do
    case Map.get(attrs, key) do
      nil -> :ok
      value -> if MapSet.member?(allowed, value), do: :ok, else: invalid("#{key} is invalid")
    end
  end

  defp validate_atom(attrs, key) do
    case Map.get(attrs, key) do
      nil -> :ok
      value when is_atom(value) -> :ok
      _ -> invalid("#{key} must be an atom")
    end
  end

  defp validate_labels(attrs) do
    case Map.get(attrs, :safe_labels, %{}) do
      value when is_map(value) -> :ok
      _ -> invalid("safe_labels must be a map")
    end
  end

  defp invalid(message), do: {:error, Surface.error(:invalid_projection, message)}

  defp fields, do: @fields
end
