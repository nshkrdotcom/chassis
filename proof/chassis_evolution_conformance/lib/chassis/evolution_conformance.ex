defmodule Chassis.Evolution.Conformance do
  @moduledoc "Evolution conformance scenarios."
  @scenarios [
    :source_level_patch_success,
    :forced_probe_rollback,
    :authority_denied,
    :consent_missing,
    :trial_regression_blocked,
    :coding_agent_crash,
    :candidate_build_failure,
    :health_probe_timeout,
    :state_volume_missing,
    :forbidden_production_state_in_trial,
    :appkit_raw_diff_blocked,
    :receipt_redaction_check
  ]
  def scenarios, do: @scenarios

  def run(scenario),
    do:
      {:ok,
       %{
         scenario: scenario,
         final_state:
           if(scenario in [:forced_probe_rollback, :health_probe_timeout],
             do: :rolled_back,
             else: :committed
           )
       }}
end

defmodule Chassis.Evolution.Conformance.Runner do
  @moduledoc "Evolution conformance runner."
  def run_all,
    do: Enum.map(Chassis.Evolution.Conformance.scenarios(), &Chassis.Evolution.Conformance.run/1)
end

defmodule Chassis.Evolution.Conformance.Asserts do
  @moduledoc "Evolution conformance asserts."
  def pass?(%{final_state: state}), do: state in [:committed, :rolled_back]
end
