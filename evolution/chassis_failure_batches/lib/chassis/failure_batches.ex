defmodule Chassis.FailureBatches do
  @moduledoc "Failure batch ingestion facade."
  @spec create_batch(map()) :: {:ok, map()}
  def create_batch(attrs) do
    summary = Map.get(attrs, :summary, %{bytes: "smoke", max_bytes: 4096})

    {:ok,
     %{
       failure_batch_ref: Map.get(attrs, :failure_batch_ref, "fb:dev:smoke"),
       tenant_ref: Map.get(attrs, :tenant_ref, "tenant:dev"),
       installation_ref: Map.get(attrs, :installation_ref, "installation:dev"),
       evidence_refs: Map.get(attrs, :evidence_refs, []),
       summary: summary,
       redaction_posture: :default
     }}
  end

  def fixture,
    do: %{
      tenant_ref: "tenant:dev",
      installation_ref: "installation:dev",
      evidence_refs: ["ev:smoke:1"]
    }
end

for source <- [Mezzanine, AppKit, AITrace, Observability, StackLab] do
  defmodule Module.concat(Chassis.FailureBatches.Source, source) do
    @moduledoc "Failure batch source adapter."
    def ingest(attrs),
      do: Chassis.FailureBatches.create_batch(Map.put(attrs, :source, inspect(__MODULE__)))
  end
end
