defmodule Chassis.Package.ModelCache do
  @moduledoc "Model cache index"

  @spec package_ref() :: String.t()
  def package_ref, do: "chassis_model_cache"

  @spec implemented?() :: boolean()
  def implemented?, do: true
end
