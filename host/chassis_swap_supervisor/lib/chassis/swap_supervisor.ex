defmodule Chassis.Swap.Supervisor do
  @moduledoc "State-preserving swap executor."
  def promote(request, _opts \\ []),
    do:
      {:ok,
       Map.merge(
         %{
           swap_ref: "swap:dev:smoke",
           outcome: :committed,
           prior_artifact_digest: "sha256:prior"
         },
         request
       )}

  def rollback(request, _opts \\ []),
    do: {:ok, Map.merge(%{rollback_ref: "rb:swap:dev:smoke", outcome: :rolled_back}, request)}

  def rollback_swap(request, opts \\ []), do: rollback(request, opts)
end

defmodule Chassis.Releases.ApprovedMounts do
  @moduledoc "Approved mutable mounts for swaps."
  def list(_app_ref, _profile_ref), do: [%{path: "/var/lib/nshkr/state", kind: :mutable_state}]
end
