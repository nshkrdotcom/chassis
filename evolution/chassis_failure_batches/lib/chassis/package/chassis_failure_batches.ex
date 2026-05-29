defmodule Chassis.Package.FailureBatches do
  @moduledoc "Failure batch ingestion"

  @spec package_ref() :: String.t()
  def package_ref, do: "chassis_failure_batches"

  @spec implemented?() :: boolean()
  def implemented?, do: true
end
