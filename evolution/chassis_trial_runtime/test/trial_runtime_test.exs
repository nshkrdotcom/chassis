defmodule Chassis.Trial.RuntimeTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Chassis.Evolution.DTO.CandidatePatch
  alias Chassis.Trial.{IsolationProfile, Runtime}

  test "fixture provider provisions isolated trials with unique node names cookies and port ranges" do
    patch = candidate_patch()

    assert {:ok, first} =
             Runtime.provision_trial(:fixture, patch, approved_state_volume_mounts: [])

    assert {:ok, second} =
             Runtime.provision_trial(:fixture, patch, approved_state_volume_mounts: [])

    assert first.trial_ref =~ "trial:cand:dev:smoke:"
    assert first.trial_node_ref != second.trial_node_ref
    assert first.isolation.cookie_ref != second.isolation.cookie_ref
    assert first.isolation.port_range != second.isolation.port_range
    assert first.provider == :fixture
  end

  test "production state mounts are rejected before provider start" do
    patch = candidate_patch()

    assert {:error, :forbidden_production_state_in_trial} =
             Runtime.provision_trial(:fixture, patch,
               approved_state_volume_mounts: ["/var/lib/prod/app"],
               state_volume_mounts: ["/var/lib/prod/app/db"]
             )
  end

  test "teardown removes active trial records" do
    patch = candidate_patch()

    assert {:ok, trial} =
             Runtime.provision_trial(:fixture, patch, approved_state_volume_mounts: [])

    assert {:ok, stopped} = Runtime.teardown_trial(trial.trial_ref)
    assert stopped.torn_down? == true
    assert Runtime.teardown_trial(trial.trial_ref) == {:error, :not_found}
  end

  test "all Phase 26 providers use isolated fixture lifecycle until Phase 27 materializers are attached" do
    patch = candidate_patch()

    for kind <- [:fixture, :container, :systemd, :ssh] do
      assert {:ok, trial} = Runtime.provision_trial(kind, patch, approved_state_volume_mounts: [])
      assert trial.provider == kind
      assert trial.isolation.beam_node_name =~ "trial-cand_dev_smoke"
      assert {:ok, _stopped} = Runtime.teardown_trial(trial.trial_ref)
    end
  end

  test "package-local Mix task emits structural JSON for fixture trials" do
    Mix.Task.reenable("chassis.node.trial")

    output =
      capture_io(fn ->
        Mix.Tasks.Chassis.Node.Trial.run([
          "--candidate-ref",
          "cand:dev:smoke",
          "--diff-path",
          "test/fixtures/empty.patch",
          "--kind",
          "fixture",
          "--json"
        ])
      end)

    assert {:ok, decoded} = Jason.decode(output)
    assert decoded["trial_ref"] =~ "trial:cand:dev:smoke:"
    assert decoded["provider"] == "fixture"
  end

  test "IsolationProfile rejects invalid state mount overlap directly" do
    profile = IsolationProfile.default("cand:dev:smoke")

    assert {:error, :forbidden_production_state_in_trial} =
             IsolationProfile.validate_mounts(profile,
               approved_state_volume_mounts: ["/srv/prod"],
               state_volume_mounts: ["/srv/prod/state"]
             )
  end

  defp candidate_patch do
    CandidatePatch.new!(%{
      candidate_ref: "cand:dev:smoke",
      base_release_ref: "release:base",
      patch_digest: "sha256:patch",
      diff_ref: "diff:dev:smoke",
      failure_batch_ref: "failure_batch:phase26",
      created_at: DateTime.utc_now()
    })
  end
end
