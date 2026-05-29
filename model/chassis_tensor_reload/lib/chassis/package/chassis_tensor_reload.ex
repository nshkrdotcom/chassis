defmodule Chassis.Package.TensorReload do
  @moduledoc "Tensor patch reload and rollback"

  @spec package_ref() :: String.t()
  def package_ref, do: "chassis_tensor_reload"

  @spec implemented?() :: boolean()
  def implemented?, do: true
end
