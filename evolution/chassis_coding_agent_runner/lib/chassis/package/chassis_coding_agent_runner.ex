defmodule Chassis.Package.CodingAgentRunner do
  @moduledoc "External coding-agent runner"

  @spec package_ref() :: String.t()
  def package_ref, do: "chassis_coding_agent_runner"

  @spec implemented?() :: boolean()
  def implemented?, do: true
end
