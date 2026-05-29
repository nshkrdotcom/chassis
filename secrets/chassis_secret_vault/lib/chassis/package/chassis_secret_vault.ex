defmodule Chassis.Package.SecretVault do
  @moduledoc "Vault materializer stub"

  @spec package_ref() :: String.t()
  def package_ref, do: "chassis_secret_vault"

  @spec implemented?() :: boolean()
  def implemented?, do: true
end
