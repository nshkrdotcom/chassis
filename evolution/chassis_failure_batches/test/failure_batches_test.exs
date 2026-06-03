defmodule Chassis.FailureBatchesTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Chassis.Evolution.DTO.FailureBatch
  alias Chassis.Evolution.Receipts.FailureBatchRecord
  alias Chassis.Evolution.Receipts.Store.Memory

  @raw_transcript "RAW TRANSCRIPT SECRET phase23 should never be stored in Chassis"

  setup do
    {:ok, store} = Memory.start_link(name: nil)
    %{store: store}
  end

  test "each source materializes a redacted FailureBatch with stable digest and receipt", %{
    store: store
  } do
    for {source, attrs} <- source_cases() do
      assert {:ok, first} = source.ingest(attrs, receipt_store: store)
      assert {:ok, second} = source.ingest(attrs, receipt_store: store)

      assert %FailureBatch{} = first
      assert first.failure_batch_ref == second.failure_batch_ref
      assert first.tenant_ref == "tenant:dev"
      assert first.installation_ref == "installation:dev"
      assert first.evidence_refs != []
      assert first.redaction_posture in [:default, :strict]
      refute contains_raw?(first)

      assert {:ok, receipt} =
               Memory.get(store, "receipt:failure_batch:#{first.failure_batch_ref}")

      assert %FailureBatchRecord{} = receipt
      assert receipt.failure_batch_ref == first.failure_batch_ref
      assert receipt.source == source.source_ref()
      refute contains_raw?(receipt)
    end
  end

  test "create_batch rejects tenant residency violations before writing receipts", %{store: store} do
    attrs =
      base_attrs(:mezzanine)
      |> Map.merge(%{
        source_region: "eu-central",
        residency_contract: %{
          residency_ref: "residency:us-only",
          allowed_regions: ["us-west"],
          default_failure_posture: :fail_closed
        }
      })

    assert {:error, {:residency_violation, error}} =
             Chassis.FailureBatches.create_batch(attrs, receipt_store: store)

    assert error.residency_ref == "residency:us-only"
    assert Memory.list(store) == []
  end

  test "link_evidence appends evidence refs without exposing raw transcript bytes", %{
    store: store
  } do
    assert {:ok, batch} =
             Chassis.FailureBatches.create_batch(base_attrs(:stack_lab), receipt_store: store)

    assert {:ok, linked} =
             Chassis.FailureBatches.link_evidence(
               batch.failure_batch_ref,
               ["evidence:stack_lab:rerun"],
               receipt_store: store
             )

    assert "evidence:stack_lab:rerun" in linked.evidence_refs
    refute contains_raw?(linked)
  end

  test "package-local Mix tasks list and show batches as structural JSON" do
    Mix.Task.reenable("chassis.evolution.batches")
    output = capture_io(fn -> Mix.Tasks.Chassis.Evolution.Batches.run(["--json"]) end)
    assert {:ok, decoded} = Jason.decode(output)
    assert [%{"failure_batch_ref" => batch_ref} | _] = decoded["items"]

    Mix.Task.reenable("chassis.evolution.batch.show")

    output =
      capture_io(fn ->
        Mix.Tasks.Chassis.Evolution.Batch.Show.run(["--batch-ref", batch_ref, "--json"])
      end)

    assert {:ok, shown} = Jason.decode(output)
    assert shown["failure_batch_ref"] == batch_ref
    refute contains_raw?(shown)
  end

  defp source_cases do
    [
      {Chassis.FailureBatches.Source.Mezzanine, base_attrs(:mezzanine)},
      {Chassis.FailureBatches.Source.AppKit, base_attrs(:appkit)},
      {Chassis.FailureBatches.Source.AITrace, base_attrs(:aitrace)},
      {Chassis.FailureBatches.Source.Observability, base_attrs(:observability)},
      {Chassis.FailureBatches.Source.StackLab, base_attrs(:stack_lab)}
    ]
  end

  defp base_attrs(source) do
    %{
      tenant_ref: "tenant:dev",
      installation_ref: "installation:dev",
      source: source,
      source_region: "us-west",
      source_event_ref: "event:#{source}:phase23",
      evidence_refs: ["evidence:#{source}:phase23"],
      raw_transcript: @raw_transcript,
      summary_hint: "bounded #{source} summary",
      redaction_posture: if(source == :aitrace, do: :strict, else: :default),
      flagged_by_ref: "operator:phase23"
    }
  end

  defp contains_raw?(value), do: inspect(value) =~ @raw_transcript
end
