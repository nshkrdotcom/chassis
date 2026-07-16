defmodule Chassis.Contracts.ReleaseResourceSupport do
  @moduledoc false

  @sensitive_keys MapSet.new(~w(
    access_token api_key authorization client_secret credential material password
    private_key raw_credential refresh_token secret token
  ))

  def attrs(value) when is_list(value), do: Map.new(value)
  def attrs(value) when is_map(value), do: value
  def attrs(_value), do: %{}

  def value(attrs, key, default \\ nil),
    do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))

  def string?(value), do: is_binary(value) and String.trim(value) != ""
  def string_list?(values), do: is_list(values) and Enum.all?(values, &string?/1)
  def positive_integer?(value), do: is_integer(value) and value > 0
  def non_negative_integer?(value), do: is_integer(value) and value >= 0
  def datetime?(%DateTime{}), do: true
  def datetime?(_value), do: false

  def digest?("sha256:" <> hex),
    do: byte_size(hex) == 64 and String.match?(hex, ~r/\A[0-9a-f]{64}\z/)

  def digest?(_value), do: false

  def known_fields?(attrs, fields) do
    allowed = MapSet.new(Enum.flat_map(fields, &[&1, Atom.to_string(&1)]))
    Enum.all?(Map.keys(attrs), &MapSet.member?(allowed, &1))
  end

  def safe_map?(value) when is_map(value) do
    safe_term?(value) and match?({:ok, _encoded}, Chassis.Contracts.encode(value))
  end

  def safe_map?(_value), do: false

  defp safe_term?(value) when is_map(value) do
    Enum.all?(value, fn {key, nested} ->
      normalized = key |> to_string() |> String.downcase()
      not sensitive_key?(normalized) and safe_term?(nested)
    end)
  end

  defp safe_term?(values) when is_list(values), do: Enum.all?(values, &safe_term?/1)

  defp safe_term?(value)
       when is_binary(value) or is_integer(value) or is_float(value) or is_boolean(value) or
              is_nil(value),
       do: true

  defp safe_term?(_value), do: false

  defp sensitive_key?(key),
    do: MapSet.member?(@sensitive_keys, key) or String.starts_with?(key, "raw_")
end

defmodule Chassis.Contracts.ReleaseProfile do
  @moduledoc "Immutable release bill of materials consumed by Chassis placement."

  alias Chassis.Contracts.ReleaseResourceSupport, as: S

  @fields [
    :contract_version,
    :release_ref,
    :artifact_ref,
    :artifact_digest,
    :version,
    :producer_revision,
    :contract_revisions,
    :migration_revisions,
    :capability_refs,
    :created_at
  ]
  @enforce_keys @fields
  defstruct @fields

  @type t :: %__MODULE__{}

  def new(attrs) when is_map(attrs) or is_list(attrs) do
    attrs = S.attrs(attrs)

    profile = %__MODULE__{
      contract_version: S.value(attrs, :contract_version, 1),
      release_ref: S.value(attrs, :release_ref),
      artifact_ref: S.value(attrs, :artifact_ref),
      artifact_digest: S.value(attrs, :artifact_digest),
      version: S.value(attrs, :version),
      producer_revision: S.value(attrs, :producer_revision),
      contract_revisions: S.value(attrs, :contract_revisions),
      migration_revisions: S.value(attrs, :migration_revisions),
      capability_refs: S.value(attrs, :capability_refs, []),
      created_at: S.value(attrs, :created_at)
    }

    strings = [
      profile.release_ref,
      profile.artifact_ref,
      profile.version,
      profile.producer_revision
    ]

    if S.known_fields?(attrs, @fields) and profile.contract_version == 1 and
         Enum.all?(strings, &S.string?/1) and
         S.digest?(profile.artifact_digest) and S.safe_map?(profile.contract_revisions) and
         S.safe_map?(profile.migration_revisions) and S.string_list?(profile.capability_refs) and
         S.datetime?(profile.created_at) do
      {:ok, profile}
    else
      {:error, :invalid_release_profile}
    end
  end

  def new(_attrs), do: {:error, :invalid_release_profile}

  def new!(attrs) do
    case new(attrs) do
      {:ok, profile} -> profile
      {:error, reason} -> raise ArgumentError, Atom.to_string(reason)
    end
  end

  def dump(%__MODULE__{} = profile), do: Map.from_struct(profile)
end

defmodule Chassis.Contracts.ResourceRequest do
  @moduledoc "Bounded resource request for deterministic Chassis placement."

  alias Chassis.Contracts.ReleaseResourceSupport, as: S

  @target_classes ~w(local_host remote_host)
  @fields [
    :contract_version,
    :resource_request_ref,
    :tenant_ref,
    :workload_ref,
    :release_ref,
    :target_class,
    :cpu_millis,
    :memory_bytes,
    :disk_bytes,
    :volume_refs,
    :network_refs,
    :constraints
  ]
  @enforce_keys @fields
  defstruct @fields

  @type t :: %__MODULE__{}

  def new(attrs) when is_map(attrs) or is_list(attrs) do
    attrs = S.attrs(attrs)

    request = %__MODULE__{
      contract_version: S.value(attrs, :contract_version, 1),
      resource_request_ref: S.value(attrs, :resource_request_ref),
      tenant_ref: S.value(attrs, :tenant_ref),
      workload_ref: S.value(attrs, :workload_ref),
      release_ref: S.value(attrs, :release_ref),
      target_class: attrs |> S.value(:target_class) |> normalize_string(),
      cpu_millis: S.value(attrs, :cpu_millis),
      memory_bytes: S.value(attrs, :memory_bytes),
      disk_bytes: S.value(attrs, :disk_bytes),
      volume_refs: S.value(attrs, :volume_refs, []),
      network_refs: S.value(attrs, :network_refs, []),
      constraints: S.value(attrs, :constraints, %{})
    }

    strings = [
      request.resource_request_ref,
      request.tenant_ref,
      request.workload_ref,
      request.release_ref
    ]

    if S.known_fields?(attrs, @fields) and request.contract_version == 1 and
         Enum.all?(strings, &S.string?/1) and
         request.target_class in @target_classes and S.positive_integer?(request.cpu_millis) and
         S.positive_integer?(request.memory_bytes) and S.non_negative_integer?(request.disk_bytes) and
         S.string_list?(request.volume_refs) and S.string_list?(request.network_refs) and
         S.safe_map?(request.constraints) do
      {:ok, request}
    else
      {:error, :invalid_resource_request}
    end
  end

  def new(_attrs), do: {:error, :invalid_resource_request}

  def new!(attrs) do
    case new(attrs) do
      {:ok, request} -> request
      {:error, reason} -> raise ArgumentError, Atom.to_string(reason)
    end
  end

  defp normalize_string(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_string(value), do: value
end

defmodule Chassis.Contracts.HealthObservation do
  @moduledoc "Observed release/process health; never a static success assertion."

  alias Chassis.Contracts.ReleaseResourceSupport, as: S

  @states ~w(ready degraded unhealthy absent)
  @fields [
    :contract_version,
    :observation_ref,
    :workload_ref,
    :release_ref,
    :desired_revision,
    :observed_revision,
    :state,
    :checks,
    :evidence_refs,
    :observed_at
  ]
  @enforce_keys @fields
  defstruct @fields

  @type t :: %__MODULE__{}

  def new(attrs) when is_map(attrs) or is_list(attrs) do
    attrs = S.attrs(attrs)

    observation = %__MODULE__{
      contract_version: S.value(attrs, :contract_version, 1),
      observation_ref: S.value(attrs, :observation_ref),
      workload_ref: S.value(attrs, :workload_ref),
      release_ref: S.value(attrs, :release_ref),
      desired_revision: S.value(attrs, :desired_revision),
      observed_revision: S.value(attrs, :observed_revision),
      state: attrs |> S.value(:state) |> normalize_string(),
      checks: S.value(attrs, :checks, []),
      evidence_refs: S.value(attrs, :evidence_refs, []),
      observed_at: S.value(attrs, :observed_at)
    }

    strings = [observation.observation_ref, observation.workload_ref, observation.release_ref]

    with true <- S.known_fields?(attrs, @fields),
         true <- observation.contract_version == 1,
         true <- Enum.all?(strings, &S.string?/1),
         true <- S.positive_integer?(observation.desired_revision),
         true <- S.non_negative_integer?(observation.observed_revision),
         true <- observation.state in @states,
         true <- valid_checks?(observation.checks),
         true <- S.string_list?(observation.evidence_refs),
         true <- S.datetime?(observation.observed_at),
         true <- coherent_ready_state?(observation) do
      {:ok, observation}
    else
      _other -> {:error, :invalid_health_observation}
    end
  end

  def new(_attrs), do: {:error, :invalid_health_observation}

  def new!(attrs) do
    case new(attrs) do
      {:ok, observation} -> observation
      {:error, reason} -> raise ArgumentError, Atom.to_string(reason)
    end
  end

  defp valid_checks?(checks) when is_list(checks) and checks != [] do
    Enum.all?(checks, fn check ->
      is_map(check) and S.string?(S.value(check, :check_ref)) and
        S.value(check, :status) in ["passed", "failed"] and S.safe_map?(check)
    end)
  end

  defp valid_checks?(_checks), do: false

  defp coherent_ready_state?(%__MODULE__{state: "ready"} = observation) do
    observation.desired_revision == observation.observed_revision and
      Enum.all?(observation.checks, &(S.value(&1, :status) == "passed"))
  end

  defp coherent_ready_state?(_observation), do: true

  defp normalize_string(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_string(value), do: value
end
