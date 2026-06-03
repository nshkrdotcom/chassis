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

defmodule Chassis.AppKit.Surface.Evolution.SurfaceError do
  @moduledoc "Product-safe Chassis Evolution AppKit surface error."

  @derive {Inspect, only: [:code, :message, :detail, :retry_after_ms]}
  @enforce_keys [:code, :message]
  defstruct [:code, :message, detail: %{}, retry_after_ms: nil]

  @type t :: %__MODULE__{
          code: atom(),
          message: String.t(),
          detail: map(),
          retry_after_ms: non_neg_integer() | nil
        }

  @spec new(atom(), String.t(), map(), non_neg_integer() | nil) :: t()
  def new(code, message, detail \\ %{}, retry_after_ms \\ nil)
      when is_atom(code) and is_binary(message) and is_map(detail) do
    %__MODULE__{code: code, message: message, detail: detail, retry_after_ms: retry_after_ms}
  end
end

defmodule Chassis.AppKit.Surface.Evolution.RedactedDiffRef do
  @moduledoc "Reference to lower-read diff material without exposing raw diff bytes."

  alias Chassis.AppKit.Surface.Evolution.SurfaceError

  @derive {Inspect, only: [:diff_ref, :digest_ref, :lower_read_lease_ref, :lease_required?]}
  @enforce_keys [:diff_ref]
  defstruct [:diff_ref, :digest_ref, :lower_read_lease_ref, lease_required?: true]

  @type t :: %__MODULE__{
          diff_ref: String.t(),
          digest_ref: String.t() | nil,
          lower_read_lease_ref: String.t() | nil,
          lease_required?: boolean()
        }

  @spec new(map() | keyword() | String.t()) :: {:ok, t()} | {:error, SurfaceError.t()}
  def new(diff_ref) when is_binary(diff_ref), do: new(%{diff_ref: diff_ref})

  def new(attrs) when is_map(attrs) or is_list(attrs) do
    attrs = normalize_attrs(attrs)

    with :ok <- required_binary(attrs, :diff_ref),
         :ok <- optional_binary(attrs, :digest_ref),
         :ok <- optional_binary(attrs, :lower_read_lease_ref),
         :ok <- optional_boolean(attrs, :lease_required?) do
      {:ok,
       %__MODULE__{
         diff_ref: Map.fetch!(attrs, :diff_ref),
         digest_ref: Map.get(attrs, :digest_ref),
         lower_read_lease_ref: Map.get(attrs, :lower_read_lease_ref),
         lease_required?: Map.get(attrs, :lease_required?, true)
       }}
    end
  end

  def new(_attrs), do: invalid(:diff_ref, "diff_ref is required")

  @spec new!(map() | keyword() | String.t()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, redacted_ref} -> redacted_ref
      {:error, error} -> raise ArgumentError, message: error.message
    end
  end

  defp normalize_attrs(attrs) do
    attrs
    |> Map.new()
    |> Map.new(fn {key, value} -> {normalize_key(key), value} end)
  end

  defp normalize_key(key) when is_atom(key), do: key

  defp normalize_key(key) when is_binary(key) do
    case key do
      "lease_required?" -> :lease_required?
      _ -> String.to_existing_atom(key)
    end
  rescue
    ArgumentError -> key
  end

  defp normalize_key(key), do: key

  defp required_binary(attrs, key) do
    case Map.get(attrs, key) do
      value when is_binary(value) and value != "" -> :ok
      _ -> invalid(key, "#{key} is required")
    end
  end

  defp optional_binary(attrs, key) do
    case Map.get(attrs, key) do
      nil -> :ok
      value when is_binary(value) -> :ok
      _ -> invalid(key, "#{key} must be a string")
    end
  end

  defp optional_boolean(attrs, key) do
    case Map.get(attrs, key) do
      nil -> :ok
      value when is_boolean(value) -> :ok
      _ -> invalid(key, "#{key} must be a boolean")
    end
  end

  defp invalid(field, message) do
    {:error, SurfaceError.new(:invalid_dto, message, %{field: field})}
  end
end

defmodule Chassis.AppKit.Surface.Evolution.DTO.ScoreSummary do
  @moduledoc "Product-safe score summary for candidate and trial readback."

  @derive {Inspect, only: [:overall_score, :dimensions, :policy_refs]}
  defstruct overall_score: nil, dimensions: %{}, policy_refs: []
end

defmodule Chassis.AppKit.Surface.Evolution.DTO.CandidateSummary do
  @moduledoc "Product-safe evolution candidate summary."

  alias Chassis.AppKit.Surface.Evolution.RedactedDiffRef
  alias Chassis.AppKit.Surface.Evolution.SurfaceError
  alias Chassis.AppKit.Surface.Evolution.DTO.ScoreSummary

  @derive {Inspect,
           only: [
             :candidate_ref,
             :evolution_ref,
             :state,
             :score_summary,
             :diff_ref_redacted,
             :receipt_refs,
             :trace_refs,
             :redaction_posture,
             :operator_action_hints
           ]}
  @enforce_keys [:candidate_ref, :diff_ref_redacted]
  defstruct [
    :candidate_ref,
    :evolution_ref,
    :state,
    :score_summary,
    :diff_ref_redacted,
    receipt_refs: [],
    trace_refs: [],
    redaction_posture: :redacted,
    operator_action_hints: []
  ]

  @type t :: %__MODULE__{
          candidate_ref: String.t(),
          evolution_ref: String.t() | nil,
          state: atom() | String.t() | nil,
          score_summary: ScoreSummary.t() | map() | nil,
          diff_ref_redacted: RedactedDiffRef.t(),
          receipt_refs: [String.t()],
          trace_refs: [String.t()],
          redaction_posture: atom() | String.t(),
          operator_action_hints: [atom() | String.t()]
        }

  @spec new(map() | keyword()) :: {:ok, t()} | {:error, SurfaceError.t()}
  def new(attrs) when is_map(attrs) or is_list(attrs) do
    attrs = attrs |> Map.new() |> normalize_keys() |> drop_private_keys()

    with :ok <- required_binary(attrs, :candidate_ref),
         {:ok, diff_ref} <- redacted_diff_ref(attrs),
         :ok <- list_of_strings(attrs, :receipt_refs),
         :ok <- list_of_strings(attrs, :trace_refs) do
      {:ok,
       %__MODULE__{
         candidate_ref: Map.fetch!(attrs, :candidate_ref),
         evolution_ref: Map.get(attrs, :evolution_ref),
         state: Map.get(attrs, :state),
         score_summary: score_summary(Map.get(attrs, :score_summary)),
         diff_ref_redacted: diff_ref,
         receipt_refs: Map.get(attrs, :receipt_refs, []),
         trace_refs: Map.get(attrs, :trace_refs, []),
         redaction_posture: Map.get(attrs, :redaction_posture, :redacted),
         operator_action_hints: Map.get(attrs, :operator_action_hints, [])
       }}
    end
  end

  def new(_attrs), do: invalid(:candidate_ref, "candidate_ref is required")

  @spec new!(map() | keyword()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, summary} -> summary
      {:error, error} -> raise ArgumentError, message: error.message
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

  defp drop_private_keys(attrs) do
    Map.drop(attrs, [
      :raw_diff,
      :raw_prompt,
      :private_prompt,
      :private_transcript,
      :provider_payload,
      :credential,
      :credentials,
      :secret,
      :state_volume_path,
      "raw_diff",
      "raw_prompt",
      "private_prompt",
      "private_transcript",
      "provider_payload",
      "credential",
      "credentials",
      "secret",
      "state_volume_path"
    ])
  end

  defp required_binary(attrs, key) do
    case Map.get(attrs, key) do
      value when is_binary(value) and value != "" -> :ok
      _ -> invalid(key, "#{key} is required")
    end
  end

  defp list_of_strings(attrs, key) do
    case Map.get(attrs, key, []) do
      values when is_list(values) ->
        if Enum.all?(values, &is_binary/1),
          do: :ok,
          else: invalid(key, "#{key} must contain strings")

      _ ->
        invalid(key, "#{key} must be a list")
    end
  end

  defp redacted_diff_ref(attrs) do
    case Map.get(attrs, :diff_ref_redacted) || Map.get(attrs, :diff_ref) do
      %RedactedDiffRef{} = ref -> {:ok, ref}
      value when is_binary(value) -> RedactedDiffRef.new(value)
      value when is_map(value) or is_list(value) -> RedactedDiffRef.new(value)
      nil -> invalid(:diff_ref_redacted, "diff_ref_redacted is required")
    end
  end

  defp score_summary(%ScoreSummary{} = summary), do: summary

  defp score_summary(%{} = summary) do
    %ScoreSummary{
      overall_score: Map.get(summary, :overall_score) || Map.get(summary, "overall_score"),
      dimensions: Map.get(summary, :dimensions) || Map.get(summary, "dimensions") || %{},
      policy_refs: Map.get(summary, :policy_refs) || Map.get(summary, "policy_refs") || []
    }
  end

  defp score_summary(nil), do: nil
  defp score_summary(other), do: other

  defp invalid(field, message) do
    {:error, SurfaceError.new(:invalid_dto, message, %{field: field})}
  end

  defp fields do
    [
      :candidate_ref,
      :evolution_ref,
      :state,
      :score_summary,
      :diff_ref_redacted,
      :diff_ref,
      :receipt_refs,
      :trace_refs,
      :redaction_posture,
      :operator_action_hints
    ]
  end
end

defmodule Chassis.AppKit.Surface.Evolution do
  @moduledoc "Chassis-side behaviour and schema index for AppKit EvolutionSurface."

  @callback list_evolution_batches(term(), map(), keyword()) :: {:ok, term()} | {:error, term()}
  @callback get_evolution_batch(term(), String.t(), keyword()) :: {:ok, term()} | {:error, term()}
  @callback get_evolution_status(term(), String.t(), keyword()) ::
              {:ok, term()} | {:error, term()}
  @callback get_candidate_summary(term(), String.t(), keyword()) ::
              {:ok, term()} | {:error, term()}
  @callback get_trial_summary(term(), String.t(), keyword()) :: {:ok, term()} | {:error, term()}
  @callback request_candidate_promotion(term(), String.t(), map(), keyword()) ::
              {:ok, term()} | {:error, term()}
  @callback record_operator_consent(term(), String.t(), map(), keyword()) ::
              {:ok, term()} | {:error, term()}
  @callback get_swap_status(term(), String.t(), keyword()) :: {:ok, term()} | {:error, term()}

  @callback_names [
    :list_evolution_batches,
    :get_evolution_batch,
    :get_evolution_status,
    :get_candidate_summary,
    :get_trial_summary,
    :request_candidate_promotion,
    :record_operator_consent,
    :get_swap_status
  ]

  @spec callback_names() :: [atom()]
  def callback_names, do: @callback_names

  @spec dto_modules() :: [module()]
  def dto_modules do
    [
      __MODULE__.DTO.ScoreSummary,
      __MODULE__.DTO.CandidateSummary,
      __MODULE__.RedactedDiffRef,
      __MODULE__.SurfaceError
    ]
  end
end
