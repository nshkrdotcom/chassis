defmodule Chassis.Package.ModelAssetConformance do
  @moduledoc "Model asset conformance scenarios"

  @spec package_ref() :: String.t()
  def package_ref, do: "chassis_model_asset_conformance"

  @spec implemented?() :: boolean()
  def implemented?, do: true
end
