defmodule Chassis.Trial.Supervisor do
  @moduledoc "Trial build/start supervisor facade."
  def build_candidate(attrs),
    do: {:ok, Map.put(attrs, :candidate_image_digest, "sha256:candidate")}

  def start_trial(attrs), do: {:ok, Map.put(attrs, :trial_ref, "trial:cand:dev:smoke")}
  def stop_trial(attrs), do: {:ok, Map.put(attrs, :stopped?, true)}
end
