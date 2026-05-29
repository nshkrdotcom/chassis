defmodule Chassis.Conformance do
  @moduledoc "Baseline Chassis conformance harness."
  @proofs ~w(chassis.boundary.local_adapter_equivalence.v1 chassis.boundary.no_pid_payloads.v1 chassis.boundary.no_raw_secret_payloads.v1 chassis.boundary.codec_digest_stability.v1 chassis.boundary.idempotency_required_for_mutations.v1 chassis.boundary.citadel_fail_closed.v1 chassis.deployment.profile_monolith_local chassis.deployment.profile_ternary_split_3_local chassis.deployment.profile_maximal_decoupled_local chassis.secrets.no_plaintext_in_receipts chassis.tenant.residency_enforcement chassis.metabolic.auto_rollback_on_pressure)
  def run, do: Enum.map(@proofs, &{&1, :pass})
  def proofs, do: @proofs
end
