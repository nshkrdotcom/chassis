defmodule Chassis.Secrets.Materializer.Env do
  @moduledoc "Environment-variable materializer."
  @spec materialize(map(), keyword()) :: {:ok, map()} | {:error, :missing_env_secret}
  def materialize(secret_ref, opts \\ []) do
    env =
      Keyword.get(
        opts,
        :env,
        "CHASSIS_SECRET_" <>
          String.upcase(
            String.replace(Map.get(secret_ref, :secret_ref, "default"), ~r/[^A-Za-z0-9]/, "_")
          )
      )

    case System.get_env(env) do
      nil ->
        {:error, :missing_env_secret}

      material ->
        {:ok,
         %{
           lease_ref: "lease:env:" <> env,
           secret_ref: Map.get(secret_ref, :secret_ref),
           material: material,
           expires_at: DateTime.add(DateTime.utc_now(), 300)
         }}
    end
  end
end

defmodule Chassis.SecretEnv do
  @moduledoc "Package marker."
end
