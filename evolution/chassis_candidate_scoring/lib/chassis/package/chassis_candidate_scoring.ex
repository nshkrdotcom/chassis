defmodule Chassis.Package.CandidateScoring do
  @moduledoc "Candidate score matrix and regression gate"

  @spec package_ref() :: String.t()
  def package_ref, do: "chassis_candidate_scoring"

  @spec implemented?() :: boolean()
  def implemented?, do: true
end
