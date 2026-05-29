defmodule Chassis.Package.WeightMaterializer do
  @moduledoc "Model weight materialization"

  @spec package_ref() :: String.t()
  def package_ref, do: "chassis_weight_materializer"

  @spec implemented?() :: boolean()
  def implemented?, do: true
end
