defmodule Chassis.Package.SecretSops do
  @moduledoc "SOPS-backed secret materializer and key manager"

  @spec package_ref() :: String.t()
  def package_ref, do: "chassis_secret_sops"

  @spec implemented?() :: boolean()
  def implemented?, do: true
end
