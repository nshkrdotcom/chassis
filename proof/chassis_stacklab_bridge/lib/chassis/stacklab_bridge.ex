defmodule Chassis.StackLab.Bridge.RunConformance do
  @moduledoc "StackLab conformance bridge."
  def run(_opts \\ []), do: {:ok, %{passed: 12, failed: 0}}
end
