defmodule Chassis.FailureBatches do
  @moduledoc "Failure batch ingestion facade."

  alias Chassis.Evolution.DTO.FailureBatch
  alias Chassis.Evolution.Receipts.FailureBatchRecord
  alias Chassis.Evolution.Receipts.Store.Memory

  @max_summary_bytes 512
  @redacted_payload_keys [:raw_transcript, :raw_body, :raw_bytes, :transcript, :body, :payload]
  @sources [:mezzanine, :appkit, :aitrace, :observability, :stack_lab]

  @type create_result :: {:ok, FailureBatch.t()} | {:error, term()}

  @spec create_batch(map(), keyword()) :: create_result()
  def create_batch(attrs, opts \\ []) when is_map(attrs) do
    attrs = normalize_keys(attrs)

    with :ok <- validate_source(attrs),
         :ok <- validate_residency(attrs) do
      batch = build_batch(attrs)
      record = build_record(batch, attrs)
      {:ok, _stored} = Memory.put(receipt_store(opts), record)
      {:ok, batch}
    end
  end

  @spec link_evidence(String.t(), [String.t()], keyword()) :: create_result()
  def link_evidence(failure_batch_ref, evidence_refs, opts \\ [])
      when is_binary(failure_batch_ref) and is_list(evidence_refs) do
    store = receipt_store(opts)
    receipt_ref = "receipt:failure_batch:#{failure_batch_ref}"

    with {:ok, record} <- Memory.get(store, receipt_ref) do
      merged_evidence_refs = Enum.uniq(record.evidence_refs ++ evidence_refs)

      attrs =
        record
        |> Map.from_struct()
        |> Map.put(:evidence_refs, merged_evidence_refs)
        |> Map.put(:failure_batch_ref, failure_batch_ref)

      batch =
        FailureBatch.new!(%{
          failure_batch_ref: failure_batch_ref,
          tenant_ref: record.tenant_ref,
          installation_ref: record.installation_ref,
          evidence_refs: merged_evidence_refs,
          summary: record.summary,
          redaction_posture: record.redaction_posture,
          flagged_by_ref: record.flagged_by_ref,
          batch_hint_ref: record.batch_hint_ref,
          created_at: record.inserted_at
        })

      {:ok, _stored} = Memory.put(store, FailureBatchRecord.new!(attrs))
      {:ok, batch}
    end
  end

  @spec list_batches(keyword()) :: [FailureBatch.t()]
  def list_batches(opts \\ []) do
    opts
    |> receipt_store()
    |> Memory.list()
    |> Enum.map(&batch_from_record/1)
  end

  @spec get_batch(String.t(), keyword()) :: {:ok, FailureBatch.t()} | {:error, :not_found}
  def get_batch(failure_batch_ref, opts \\ []) when is_binary(failure_batch_ref) do
    opts
    |> receipt_store()
    |> Memory.get("receipt:failure_batch:#{failure_batch_ref}")
    |> case do
      {:ok, record} -> {:ok, batch_from_record(record)}
      {:error, :not_found} -> {:error, :not_found}
    end
  end

  @spec ensure_fixture_batch(keyword()) :: {:ok, FailureBatch.t()}
  def ensure_fixture_batch(opts \\ []) do
    case create_batch(fixture(), opts) do
      {:ok, batch} -> {:ok, batch}
      {:error, reason} -> raise "could not create fixture failure batch: #{inspect(reason)}"
    end
  end

  @spec fixture() :: map()
  def fixture do
    %{
      tenant_ref: "tenant:dev",
      installation_ref: "installation:dev",
      source: :stack_lab,
      source_region: "us-west",
      source_event_ref: "event:stack_lab:fixture",
      evidence_refs: ["evidence:stack_lab:fixture"],
      summary_hint: "bounded stack_lab fixture summary",
      redaction_posture: :default,
      flagged_by_ref: "operator:fixture",
      raw_transcript: "fixture transcript used only for digesting"
    }
  end

  @spec jsonable_batch(FailureBatch.t()) :: map()
  def jsonable_batch(%FailureBatch{} = batch) do
    %{
      failure_batch_ref: batch.failure_batch_ref,
      tenant_ref: batch.tenant_ref,
      installation_ref: batch.installation_ref,
      evidence_refs: batch.evidence_refs,
      summary: batch.summary,
      redaction_posture: Atom.to_string(batch.redaction_posture),
      flagged_by_ref: batch.flagged_by_ref,
      batch_hint_ref: batch.batch_hint_ref,
      created_at: DateTime.to_iso8601(batch.created_at)
    }
  end

  defp build_batch(attrs) do
    summary = sanitized_summary(attrs)
    evidence_refs = evidence_refs(attrs)

    FailureBatch.new!(%{
      failure_batch_ref:
        Map.get(attrs, :failure_batch_ref) || stable_ref(attrs, summary, evidence_refs),
      tenant_ref: required_attr(attrs, :tenant_ref),
      installation_ref: required_attr(attrs, :installation_ref),
      evidence_refs: evidence_refs,
      summary: summary,
      redaction_posture: redaction_posture(attrs),
      flagged_by_ref: Map.get(attrs, :flagged_by_ref),
      batch_hint_ref: Map.get(attrs, :batch_hint_ref),
      created_at: Map.get(attrs, :created_at, DateTime.utc_now())
    })
  end

  defp build_record(%FailureBatch{} = batch, attrs) do
    FailureBatchRecord.new!(%{
      failure_batch_ref: batch.failure_batch_ref,
      tenant_ref: batch.tenant_ref,
      installation_ref: batch.installation_ref,
      source: Map.fetch!(attrs, :source),
      evidence_refs: batch.evidence_refs,
      summary: batch.summary,
      redaction_posture: batch.redaction_posture,
      flagged_by_ref: batch.flagged_by_ref,
      batch_hint_ref: batch.batch_hint_ref,
      source_event_ref: Map.get(attrs, :source_event_ref),
      source_region: Map.get(attrs, :source_region),
      span_attributes: span_attributes(batch, attrs),
      projection_summary: projection_summary(batch),
      inserted_at: batch.created_at
    })
  end

  defp batch_from_record(%FailureBatchRecord{} = record) do
    FailureBatch.new!(%{
      failure_batch_ref: record.failure_batch_ref,
      tenant_ref: record.tenant_ref,
      installation_ref: record.installation_ref,
      evidence_refs: record.evidence_refs,
      summary: record.summary,
      redaction_posture: record.redaction_posture,
      flagged_by_ref: record.flagged_by_ref,
      batch_hint_ref: record.batch_hint_ref,
      created_at: record.inserted_at
    })
  end

  defp receipt_store(opts) do
    Keyword.get_lazy(opts, :receipt_store, fn ->
      case Process.whereis(Memory) do
        nil ->
          {:ok, pid} = Memory.start_link()
          pid

        pid ->
          pid
      end
    end)
  end

  defp validate_source(attrs) do
    source = Map.get(attrs, :source)

    if source in @sources do
      :ok
    else
      {:error, {:unknown_failure_batch_source, source}}
    end
  end

  defp validate_residency(attrs) do
    contract = Map.get(attrs, :residency_contract)
    source_region = Map.get(attrs, :source_region)

    cond do
      is_nil(contract) ->
        :ok

      source_region in List.wrap(
        Map.get(contract, :allowed_regions) || Map.get(contract, "allowed_regions")
      ) ->
        :ok

      true ->
        {:error,
         {:residency_violation,
          %{
            residency_ref:
              Map.get(contract, :residency_ref) || Map.get(contract, "residency_ref"),
            source_region: source_region,
            allowed_regions:
              Map.get(contract, :allowed_regions) || Map.get(contract, "allowed_regions") || [],
            posture:
              Map.get(contract, :default_failure_posture) ||
                Map.get(contract, "default_failure_posture") ||
                :fail_closed
          }}}
    end
  end

  defp sanitized_summary(attrs) do
    max_bytes = Map.get(attrs, :max_summary_bytes, @max_summary_bytes)

    bytes =
      case redaction_posture(attrs) do
        :strict -> "sha256:#{payload_digest(attrs)}"
        :default -> bounded_summary(attrs, max_bytes)
      end

    %{bytes: bytes, max_bytes: max_bytes}
  end

  defp bounded_summary(attrs, max_bytes) do
    attrs
    |> Map.get(:summary_hint, default_summary(attrs))
    |> to_string()
    |> binary_part_safe(max_bytes)
  end

  defp binary_part_safe(value, max_bytes) when byte_size(value) <= max_bytes, do: value
  defp binary_part_safe(value, max_bytes), do: binary_part(value, 0, max_bytes)

  defp default_summary(attrs), do: "failure batch from #{Map.get(attrs, :source)}"

  defp payload_digest(attrs) do
    attrs
    |> Map.take(@redacted_payload_keys ++ [:summary_hint, :source_event_ref, :evidence_refs])
    |> digest()
  end

  defp evidence_refs(attrs) do
    attrs
    |> Map.get(:evidence_refs, [])
    |> List.wrap()
    |> Kernel.++(source_event_evidence(attrs))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp source_event_evidence(%{source_event_ref: ref}) when is_binary(ref), do: [ref]
  defp source_event_evidence(_attrs), do: []

  defp redaction_posture(attrs) do
    attrs
    |> Map.get(:redaction_posture, :default)
    |> normalize_posture()
  end

  defp normalize_posture(posture) when posture in [:default, :strict], do: posture
  defp normalize_posture("default"), do: :default
  defp normalize_posture("strict"), do: :strict
  defp normalize_posture(_posture), do: :default

  defp stable_ref(attrs, summary, evidence_refs) do
    digest =
      %{
        tenant_ref: Map.get(attrs, :tenant_ref),
        installation_ref: Map.get(attrs, :installation_ref),
        source: Map.get(attrs, :source),
        source_event_ref: Map.get(attrs, :source_event_ref),
        evidence_refs: evidence_refs,
        summary: summary,
        redaction_posture: redaction_posture(attrs)
      }
      |> digest()
      |> String.slice(0, 24)

    "failure_batch:#{digest}"
  end

  defp span_attributes(%FailureBatch{} = batch, attrs) do
    %{
      "chassis.failure_batch_ref" => batch.failure_batch_ref,
      "chassis.failure_source" => Atom.to_string(Map.fetch!(attrs, :source)),
      "chassis.tenant_ref" => batch.tenant_ref
    }
  end

  defp projection_summary(%FailureBatch{} = batch) do
    %{
      failure_batch_ref: batch.failure_batch_ref,
      evidence_ref_count: length(batch.evidence_refs),
      summary_bytes: byte_size(batch.summary.bytes)
    }
  end

  defp digest(value) do
    :sha256
    |> :crypto.hash(:erlang.term_to_binary(canonical(value)))
    |> Base.encode16(case: :lower)
  end

  defp canonical(%{} = map) do
    map
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Enum.sort_by(fn {key, _value} -> to_string(key) end)
    |> Enum.map(fn {key, value} -> {to_string(key), canonical(value)} end)
  end

  defp canonical(list) when is_list(list), do: Enum.map(list, &canonical/1)
  defp canonical(atom) when is_atom(atom), do: Atom.to_string(atom)
  defp canonical(value), do: value

  defp normalize_keys(attrs) do
    known_keys =
      [
        :failure_batch_ref,
        :tenant_ref,
        :installation_ref,
        :source,
        :source_region,
        :source_event_ref,
        :evidence_refs,
        :raw_transcript,
        :raw_body,
        :raw_bytes,
        :transcript,
        :body,
        :payload,
        :summary_hint,
        :summary,
        :max_summary_bytes,
        :redaction_posture,
        :flagged_by_ref,
        :batch_hint_ref,
        :created_at,
        :residency_contract
      ]
      |> Map.new(&{Atom.to_string(&1), &1})

    Map.new(attrs, fn
      {key, value} when is_binary(key) -> {Map.get(known_keys, key, key), normalize_value(value)}
      {key, value} -> {key, normalize_value(value)}
    end)
  end

  defp normalize_value(%{} = map), do: normalize_keys(map)
  defp normalize_value(list) when is_list(list), do: Enum.map(list, &normalize_value/1)
  defp normalize_value(value), do: value

  defp required_attr(attrs, key) do
    case Map.fetch(attrs, key) do
      {:ok, value} when not is_nil(value) -> value
      _missing -> raise ArgumentError, "missing required evolution field #{key}"
    end
  end
end

for {name, source_ref} <- [
      {Mezzanine, :mezzanine},
      {AppKit, :appkit},
      {AITrace, :aitrace},
      {Observability, :observability},
      {StackLab, :stack_lab}
    ] do
  defmodule Module.concat(Chassis.FailureBatches.Source, name) do
    @moduledoc "Failure batch source adapter."
    @source_ref source_ref

    @spec source_ref() :: atom()
    def source_ref, do: @source_ref

    @spec ingest(map(), keyword()) :: Chassis.FailureBatches.create_result()
    def ingest(attrs, opts \\ []) when is_map(attrs) do
      attrs
      |> Map.put(:source, @source_ref)
      |> Chassis.FailureBatches.create_batch(opts)
    end
  end
end
