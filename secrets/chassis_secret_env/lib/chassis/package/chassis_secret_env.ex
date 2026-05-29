defmodule Chassis.Package.SecretEnv do
  @moduledoc "Environment-variable secret materializer"

  @spec package_ref() :: String.t()
  def package_ref, do: "chassis_secret_env"

  @spec implemented?() :: boolean()
  def implemented?, do: true
end
