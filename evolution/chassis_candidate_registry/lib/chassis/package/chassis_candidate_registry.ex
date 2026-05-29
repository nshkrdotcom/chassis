defmodule Chassis.Package.CandidateRegistry do
  @moduledoc "Candidate registry"

  @spec package_ref() :: String.t()
  def package_ref, do: "chassis_candidate_registry"

  @spec implemented?() :: boolean()
  def implemented?, do: true
end
