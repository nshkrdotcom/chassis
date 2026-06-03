defmodule Chassis.Trial.SupervisorTest do
  use ExUnit.Case, async: false

  alias Chassis.Trial.Supervisor, as: TrialSupervisor

  setup do
    {:ok, supervisor} = TrialSupervisor.start_link(name: nil)
    %{supervisor: supervisor}
  end

  test "build/start/stop lifecycle records active trials", %{supervisor: supervisor} do
    attrs = %{
      candidate_ref: "cand:dev:smoke",
      diff_ref: "diff:dev:smoke",
      build_strategy: :fixture
    }

    assert {:ok, image} = TrialSupervisor.build_candidate(supervisor, attrs)
    assert image.candidate_image_digest =~ "sha256:"
    assert image.build_strategy == :fixture

    assert {:ok, trial} =
             TrialSupervisor.start_trial(supervisor, Map.put(image, :provider, :fixture))

    assert trial.trial_ref =~ "trial:cand:dev:smoke:"
    assert [^trial] = TrialSupervisor.list_trials(supervisor)

    assert {:ok, stopped} = TrialSupervisor.stop_trial(supervisor, trial.trial_ref)
    assert stopped.stopped? == true
    assert [] = TrialSupervisor.list_trials(supervisor)
  end

  test "stop returns not_found for unknown trial refs", %{supervisor: supervisor} do
    assert TrialSupervisor.stop_trial(supervisor, "trial:missing") == {:error, :not_found}
  end
end
