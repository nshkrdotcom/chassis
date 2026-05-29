defmodule Chassis.Package.K8s do
  @moduledoc "Kubernetes adapter stub"

  @spec package_ref() :: String.t()
  def package_ref, do: "chassis_k8s"

  @spec implemented?() :: boolean()
  def implemented?, do: true
end
