defmodule Chassis.AppKit.SurfaceTest do
  use ExUnit.Case, async: true

  alias Chassis.AppKit.Surface
  alias Chassis.AppKit.Surface.Evolution
  alias Chassis.AppKit.Surface.Evolution.DTO.CandidateSummary
  alias Chassis.AppKit.Surface.Evolution.RedactedDiffRef
  alias Chassis.AppKit.Surface.Evolution.SurfaceError

  test "projection structs validate required deployment readback fields" do
    assert {:ok, projection} =
             Surface.Projection.new(%{
               deployment_ref: "deployment:demo",
               app_ref: "app:demo:installation:acme:demo:tenant:dev",
               app_atom: :demo,
               tenant_ref: "tenant:dev",
               installation_ref: "installation:acme:demo",
               active_profile: "profile:monolith",
               health_status: :healthy,
               receipt_ref: "receipt:deployment:1",
               status: :active
             })

    assert projection.active_profile == "profile:monolith"
    assert projection.health_status == :healthy
  end

  test "projection validation fails closed without profile context" do
    assert {:error, %Surface.Error{code: :invalid_projection, safe_message: message}} =
             Surface.Projection.new(%{app_ref: "app:demo"})

    assert message =~ "active_profile"
  end

  test "package marker exposes schema modules without static implemented flag" do
    assert Chassis.Package.AppkitSurface.package_ref() == "chassis_appkit_surface"
    assert Chassis.Package.AppkitSurface.projection_module() == Surface.Projection
    assert Chassis.Package.AppkitSurface.error_module() == Surface.Error
    assert Chassis.Package.AppkitSurface.evolution_module() == Surface.Evolution
  end

  test "evolution behaviour exposes the eight product surface callbacks" do
    assert Evolution.callback_names() == [
             :list_evolution_batches,
             :get_evolution_batch,
             :get_evolution_status,
             :get_candidate_summary,
             :get_trial_summary,
             :request_candidate_promotion,
             :record_operator_consent,
             :get_swap_status
           ]
  end

  test "candidate summaries keep raw diffs and private prompt material out of the DTO" do
    assert {:ok, summary} =
             CandidateSummary.new(%{
               candidate_ref: "candidate:repair:1",
               state: :scored,
               score_summary: %{overall_score: 0.91, dimensions: %{tests: 1.0}},
               receipt_refs: ["receipt:evolution:candidate:1"],
               redaction_posture: :redacted,
               diff_ref_redacted: %{diff_ref: "diff:candidate:1"},
               raw_diff: "--- private diff ---",
               private_prompt: "repair the secret prompt",
               provider_payload: %{token: "secret"}
             })

    assert summary.candidate_ref == "candidate:repair:1"

    assert %RedactedDiffRef{diff_ref: "diff:candidate:1", lease_required?: true} =
             summary.diff_ref_redacted

    refute Map.has_key?(Map.from_struct(summary), :raw_diff)
    refute inspect(summary) =~ "private diff"
    refute inspect(summary) =~ "secret prompt"
  end

  test "candidate summary validation fails closed without a candidate ref" do
    assert {:error, %SurfaceError{code: :invalid_dto, message: message, detail: detail}} =
             CandidateSummary.new(%{state: :scored, raw_diff: "not exposed"})

    assert message =~ "candidate_ref"
    assert detail.field == :candidate_ref
  end
end
