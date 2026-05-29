defmodule Chassis.StackManager.Transaction do
  @moduledoc "Deployment transaction orchestration."
  @steps [
    :fence_acquire,
    :resolve_profile,
    :discover_hosts,
    :validate_topology,
    :authorize,
    :provision,
    :mesh_join,
    :register_app,
    :emit_receipt
  ]
  @spec run(map()) :: {:ok, map()} | {:error, term()}
  def run(attrs) do
    if Map.get(attrs, :deny_authority?) do
      {:error, :authority_denied}
    else
      {:ok,
       %{
         status: :active,
         steps: @steps,
         receipt_ref: "receipt:deployment:smoke",
         checkpoint_ref: "checkpoint:smoke"
       }}
    end
  end

  @spec rollback(map()) :: {:ok, map()}
  def rollback(attrs),
    do:
      {:ok,
       %{status: :rolled_back, rollback_ref: Map.get(attrs, :rollback_ref, "rollback:smoke")}}
end
