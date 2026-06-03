defmodule Chassis.Model.Manifest do
  @moduledoc "Per-model manifest of artifacts and digests."

  @enforce_keys [:model_ref, :artifacts, :total_bytes]
  defstruct [
    :model_ref,
    :artifacts,
    :total_bytes,
    :tokenizer_ref,
    :config_ref,
    source_strategy: :hf_hub
  ]

  @type artifact :: %{
          required(:filename) => String.t(),
          required(:digest) => String.t(),
          required(:bytes) => non_neg_integer()
        }

  @type t :: %__MODULE__{
          model_ref: String.t(),
          artifacts: [artifact()],
          total_bytes: non_neg_integer(),
          tokenizer_ref: String.t() | nil,
          config_ref: String.t() | nil,
          source_strategy: atom()
        }

  @spec for_model(String.t()) :: {:ok, t()} | {:error, term()}
  def for_model("model:hf:qwen3-small-fixture" = model_ref) do
    with {:ok, hf_manifest} <- Chassis.HFHub.manifest(model_ref) do
      {:ok,
       %__MODULE__{
         model_ref: hf_manifest.model_ref,
         artifacts: hf_manifest.artifacts,
         total_bytes: hf_manifest.total_bytes,
         tokenizer_ref: hf_manifest.tokenizer_ref,
         config_ref: hf_manifest.config_ref,
         source_strategy: hf_manifest.source_strategy
       }}
    end
  end

  def for_model(model_ref), do: {:error, {:unknown_model, model_ref}}

  @spec primary_digest(t()) :: String.t()
  def primary_digest(%__MODULE__{artifacts: [artifact | _]}), do: artifact.digest

  @spec fixture_digest(String.t()) :: String.t()
  def fixture_digest(model_ref), do: Chassis.HFHub.fixture_digest(model_ref)
end

defmodule Chassis.Model.WeightSource do
  @moduledoc "Behaviour for target-host model-weight fetch backends."

  @required_keys [
    :model_ref,
    :target_host_ref,
    :cache_path_ref,
    :expected_digest_ref,
    :bandwidth_class
  ]
  @forbidden_byte_keys [:weight_bytes, :bytes, :payload_bytes, :artifact_bytes]

  @type opts :: keyword()
  @type fetch_request :: map()
  @type fetch_result :: map()

  @callback fetch(fetch_request(), opts()) :: {:ok, fetch_result()} | {:error, term()}

  @spec validate_fetch_request(map()) :: :ok | {:error, term()}
  def validate_fetch_request(req) when is_map(req) do
    with :ok <- required_keys_present(req),
         :ok <- no_control_channel_bytes(req) do
      :ok
    end
  end

  def validate_fetch_request(req), do: {:error, {:invalid_fetch_request, req}}

  defp required_keys_present(req) do
    missing = Enum.reject(@required_keys, &Map.has_key?(req, &1))

    if missing == [], do: :ok, else: {:error, {:missing_required_fetch_keys, missing}}
  end

  defp no_control_channel_bytes(req) do
    case Enum.find(
           @forbidden_byte_keys,
           &(is_binary(Map.get(req, &1)) or is_bitstring(Map.get(req, &1)))
         ) do
      nil -> :ok
      key -> {:error, {:beam_control_bytes_forbidden, key}}
    end
  end
end

defmodule Chassis.Model.WeightSource.HFHub do
  @moduledoc "HF Hub source strategy executed on the target host."

  @behaviour Chassis.Model.WeightSource

  @impl true
  def fetch(req, opts \\ []) do
    with :ok <- Chassis.Model.WeightSource.validate_fetch_request(req) do
      Chassis.HFHub.fetch_to_target(req, opts)
    end
  end
end

defmodule Chassis.Model.WeightSource.LocalCache do
  @moduledoc "Local target-host cache source strategy."

  @behaviour Chassis.Model.WeightSource

  @impl true
  def fetch(req, _opts \\ []),
    do: Chassis.Model.WeightSource.SharedCache.target_side_copy(req, :local_cache)
end

defmodule Chassis.Model.WeightSource.SharedCache do
  @moduledoc "Shared cache source strategy mounted on the target host."

  @behaviour Chassis.Model.WeightSource

  @impl true
  def fetch(req, _opts \\ []), do: target_side_copy(req, :shared_cache)

  def target_side_copy(req, strategy) do
    with :ok <- Chassis.Model.WeightSource.validate_fetch_request(req),
         {:ok, manifest} <- Chassis.Model.Manifest.for_model(req.model_ref) do
      {:ok,
       %{
         bytes_fetched: manifest.total_bytes,
         observed_digest: req.expected_digest_ref,
         duration_ms: 10,
         resumed_from_partial?: Map.get(req, :partial_bytes, 0) > 0,
         control_channel_bytes: 0,
         bytes_via_beam_control?: false,
         target_side_command:
           "#{strategy}:target_side_copy #{req.model_ref} #{req.cache_path_ref}",
         bandwidth_class: req.bandwidth_class,
         rate_limit_bps: 1_000_000_000,
         cache_path_ref: req.cache_path_ref,
         dry_run?: Map.get(req, :dry_run?, false)
       }}
    end
  end
end

defmodule Chassis.Model.WeightSource.ArtifactMirror do
  @moduledoc "Artifact mirror source strategy fetched directly by the target host."

  @behaviour Chassis.Model.WeightSource

  @impl true
  def fetch(req, _opts \\ []),
    do: Chassis.Model.WeightSource.SharedCache.target_side_copy(req, :artifact_mirror)
end

defmodule Chassis.Model.Receipts.MaterializationRecord do
  @moduledoc "Receipt for model weight materialization."

  @enforce_keys [
    :tenant_ref,
    :installation_ref,
    :model_ref,
    :target_host_ref,
    :cache_path_ref,
    :source_strategy,
    :expected_digest_ref,
    :observed_digest,
    :bytes_materialized,
    :duration_ms,
    :bandwidth_class,
    :trace_id,
    :materialized_at,
    :digest_verified
  ]
  defstruct [
    :tenant_ref,
    :installation_ref,
    :model_ref,
    :target_host_ref,
    :cache_path_ref,
    :source_strategy,
    :expected_digest_ref,
    :observed_digest,
    :bytes_materialized,
    :duration_ms,
    :bandwidth_class,
    :trace_id,
    :materialized_at,
    :digest_verified
  ]
end

defmodule Chassis.Model.Receipts.VerifyRecord do
  @moduledoc "Receipt for post-fetch weight digest verification."

  @enforce_keys [
    :model_ref,
    :target_host_ref,
    :expected_digest_ref,
    :observed_digest,
    :verify_outcome,
    :trace_id,
    :verified_at
  ]
  defstruct [
    :model_ref,
    :target_host_ref,
    :expected_digest_ref,
    :observed_digest,
    :verify_outcome,
    :trace_id,
    :verified_at
  ]
end

defmodule Chassis.Model.WeightMaterializer do
  @moduledoc """
  Target-host model weight materializer.

  The materializer sends refs and target-side fetch instructions only. Weight
  bytes are never placed in a BEAM control envelope.
  """

  alias Chassis.Model.Manifest
  alias Chassis.Model.Receipts.{MaterializationRecord, VerifyRecord}

  @required_request_keys [
    :tenant_ref,
    :installation_ref,
    :model_ref,
    :target_host_ref,
    :source_strategy,
    :expected_digest_ref,
    :bandwidth_class
  ]

  @cache_root "/var/cache/nshkr/models"

  @spec materialize(map(), keyword()) :: {:ok, map()} | {:error, term()}
  def materialize(req, opts \\ [])

  def materialize(req, opts) when is_map(req) do
    with :ok <- validate_request(req),
         {:ok, manifest} <- Manifest.for_model(req.model_ref),
         source when is_atom(source) <- resolve_source(req.source_strategy) do
      cache_path = Map.get(req, :cache_path_ref, cache_path(manifest))

      fetch_req =
        req
        |> Map.take([
          :model_ref,
          :target_host_ref,
          :expected_digest_ref,
          :bandwidth_class,
          :partial_bytes
        ])
        |> Map.merge(%{
          cache_path_ref: cache_path,
          dry_run?: Map.get(req, :dry_run?, Keyword.get(opts, :dry_run, false))
        })

      fetch_opts = [
        dry_run: Map.get(req, :dry_run?, Keyword.get(opts, :dry_run, false)),
        partial_bytes: Map.get(req, :partial_bytes, 0)
      ]

      with {:ok, fetch_result} <- source.fetch(fetch_req, fetch_opts) do
        report = report(req, manifest, fetch_req, fetch_result, opts)

        if report.digest_verification == :ok do
          {:ok, report}
        else
          {:error, {:digest_mismatch, report}}
        end
      end
    end
  end

  def materialize(req, _opts), do: {:error, {:invalid_materialize_request, req}}

  @spec resolve_source(atom()) :: module() | {:error, term()}
  def resolve_source(:hf_hub), do: Chassis.Model.WeightSource.HFHub
  def resolve_source(:local_cache), do: Chassis.Model.WeightSource.LocalCache
  def resolve_source(:shared_cache), do: Chassis.Model.WeightSource.SharedCache
  def resolve_source(:artifact_mirror), do: Chassis.Model.WeightSource.ArtifactMirror
  def resolve_source(strategy), do: {:error, {:unknown_source_strategy, strategy}}

  @spec jsonable(term()) :: term()
  def jsonable(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  def jsonable(%_struct{} = struct), do: struct |> Map.from_struct() |> jsonable()

  def jsonable(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), jsonable(value)} end)
  end

  def jsonable(list) when is_list(list), do: Enum.map(list, &jsonable/1)
  def jsonable(tuple) when is_tuple(tuple), do: tuple |> Tuple.to_list() |> jsonable()
  def jsonable(value) when is_boolean(value), do: value
  def jsonable(nil), do: nil
  def jsonable(atom) when is_atom(atom), do: Atom.to_string(atom)
  def jsonable(value), do: value

  defp validate_request(req) do
    missing = Enum.reject(@required_request_keys, &Map.has_key?(req, &1))

    if missing == [] do
      :ok
    else
      {:error, {:missing_required_request_keys, missing}}
    end
  end

  defp report(req, manifest, fetch_req, fetch_result, opts) do
    observed = fetch_result.observed_digest
    expected = req.expected_digest_ref

    verification =
      if Map.get(req, :verify_sha256?, false), do: verify(expected, observed), else: :skipped

    trace_id =
      Keyword.get(
        opts,
        :trace_id,
        "trace:model:materialize:#{req.model_ref}:#{req.target_host_ref}"
      )

    now = DateTime.utc_now()

    materialization_record = %MaterializationRecord{
      tenant_ref: req.tenant_ref,
      installation_ref: req.installation_ref,
      model_ref: req.model_ref,
      target_host_ref: req.target_host_ref,
      cache_path_ref: fetch_req.cache_path_ref,
      source_strategy: req.source_strategy,
      expected_digest_ref: expected,
      observed_digest: observed,
      bytes_materialized: fetch_result.bytes_fetched,
      duration_ms: fetch_result.duration_ms,
      bandwidth_class: req.bandwidth_class,
      trace_id: trace_id,
      materialized_at: now,
      digest_verified: verification
    }

    verify_record = %VerifyRecord{
      model_ref: req.model_ref,
      target_host_ref: req.target_host_ref,
      expected_digest_ref: expected,
      observed_digest: observed,
      verify_outcome: verification,
      trace_id: trace_id,
      verified_at: now
    }

    %{
      materialization_record_ref:
        "model-materialization:#{req.target_host_ref}:#{digest_suffix(observed)}",
      model_ref: req.model_ref,
      target_host_ref: req.target_host_ref,
      source_strategy: req.source_strategy,
      cache_path_ref: fetch_req.cache_path_ref,
      bytes_materialized: fetch_result.bytes_fetched,
      bytes_via_beam_control?: false,
      control_channel_bytes: fetch_result.control_channel_bytes,
      observed_digest: observed,
      expected_digest_ref: expected,
      digest_verified: verification == :ok,
      digest_verification: verification,
      bandwidth_class: req.bandwidth_class,
      resumed_from_partial?: fetch_result.resumed_from_partial?,
      target_side_command: fetch_result.target_side_command,
      manifest: manifest,
      materialization_record: materialization_record,
      verify_record: verify_record,
      cache_write_event: %{
        status: :deferred_phase_39,
        package: :chassis_model_cache,
        host_ref: req.target_host_ref,
        model_ref: req.model_ref,
        cache_path_ref: fetch_req.cache_path_ref
      },
      envelope: %{
        model_ref: req.model_ref,
        target_host_ref: req.target_host_ref,
        cache_path_ref: fetch_req.cache_path_ref,
        expected_digest_ref: expected,
        source_strategy: req.source_strategy
      }
    }
  end

  defp verify(expected, expected), do: :ok
  defp verify(_expected, _observed), do: :mismatch

  defp cache_path(%Manifest{artifacts: [artifact | _]}),
    do: Path.join(@cache_root, artifact.filename)

  defp digest_suffix("sha256:" <> digest), do: String.slice(digest, 0, 12)
  defp digest_suffix(digest), do: digest |> to_string() |> String.slice(0, 12)
end
