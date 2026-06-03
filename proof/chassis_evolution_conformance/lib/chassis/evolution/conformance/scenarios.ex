defmodule Chassis.Evolution.Conformance.Scenarios.SourceLevelPatchSuccess do
  @moduledoc false

  @behaviour Chassis.Evolution.Conformance.Scenario

  alias Chassis.Evolution.Conformance.Evidence

  @impl true
  def name, do: :source_level_patch_success

  @impl true
  def run(opts), do: Evidence.build(name(), opts)
end

defmodule Chassis.Evolution.Conformance.Scenarios.ForcedProbeRollback do
  @moduledoc false

  @behaviour Chassis.Evolution.Conformance.Scenario

  alias Chassis.Evolution.Conformance.Evidence

  @impl true
  def name, do: :forced_probe_rollback

  @impl true
  def run(opts), do: Evidence.build(name(), opts)
end

defmodule Chassis.Evolution.Conformance.Scenarios.AuthorityDenied do
  @moduledoc false

  @behaviour Chassis.Evolution.Conformance.Scenario

  alias Chassis.Evolution.Conformance.Evidence

  @impl true
  def name, do: :authority_denied

  @impl true
  def run(opts), do: Evidence.build(name(), opts)
end

defmodule Chassis.Evolution.Conformance.Scenarios.ConsentMissing do
  @moduledoc false

  @behaviour Chassis.Evolution.Conformance.Scenario

  alias Chassis.Evolution.Conformance.Evidence

  @impl true
  def name, do: :consent_missing

  @impl true
  def run(opts), do: Evidence.build(name(), opts)
end

defmodule Chassis.Evolution.Conformance.Scenarios.TrialRegressionBlocked do
  @moduledoc false

  @behaviour Chassis.Evolution.Conformance.Scenario

  alias Chassis.Evolution.Conformance.Evidence

  @impl true
  def name, do: :trial_regression_blocked

  @impl true
  def run(opts), do: Evidence.build(name(), opts)
end

defmodule Chassis.Evolution.Conformance.Scenarios.CodingAgentCrash do
  @moduledoc false

  @behaviour Chassis.Evolution.Conformance.Scenario

  alias Chassis.Evolution.Conformance.Evidence

  @impl true
  def name, do: :coding_agent_crash

  @impl true
  def run(opts), do: Evidence.build(name(), opts)
end

defmodule Chassis.Evolution.Conformance.Scenarios.CandidateBuildFailure do
  @moduledoc false

  @behaviour Chassis.Evolution.Conformance.Scenario

  alias Chassis.Evolution.Conformance.Evidence

  @impl true
  def name, do: :candidate_build_failure

  @impl true
  def run(opts), do: Evidence.build(name(), opts)
end

defmodule Chassis.Evolution.Conformance.Scenarios.HealthProbeTimeout do
  @moduledoc false

  @behaviour Chassis.Evolution.Conformance.Scenario

  alias Chassis.Evolution.Conformance.Evidence

  @impl true
  def name, do: :health_probe_timeout

  @impl true
  def run(opts), do: Evidence.build(name(), opts)
end

defmodule Chassis.Evolution.Conformance.Scenarios.StateVolumeMissing do
  @moduledoc false

  @behaviour Chassis.Evolution.Conformance.Scenario

  alias Chassis.Evolution.Conformance.Evidence

  @impl true
  def name, do: :state_volume_missing

  @impl true
  def run(opts), do: Evidence.build(name(), opts)
end

defmodule Chassis.Evolution.Conformance.Scenarios.ForbiddenProductionStateInTrial do
  @moduledoc false

  @behaviour Chassis.Evolution.Conformance.Scenario

  alias Chassis.Evolution.Conformance.Evidence

  @impl true
  def name, do: :forbidden_production_state_in_trial

  @impl true
  def run(opts), do: Evidence.build(name(), opts)
end

defmodule Chassis.Evolution.Conformance.Scenarios.AppkitRawDiffBlocked do
  @moduledoc false

  @behaviour Chassis.Evolution.Conformance.Scenario

  alias Chassis.Evolution.Conformance.Evidence

  @impl true
  def name, do: :appkit_raw_diff_blocked

  @impl true
  def run(opts), do: Evidence.build(name(), opts)
end

defmodule Chassis.Evolution.Conformance.Scenarios.ReceiptRedactionCheck do
  @moduledoc false

  @behaviour Chassis.Evolution.Conformance.Scenario

  alias Chassis.Evolution.Conformance.Evidence

  @impl true
  def name, do: :receipt_redaction_check

  @impl true
  def run(opts), do: Evidence.build(name(), opts)
end
