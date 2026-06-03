defmodule Chassis.Secrets.Materializer.Env do
  @moduledoc """
  Environment-variable secret materializer.

  This backend is for local development and process-injected secrets. It never
  derives fallback material: if the env var is missing, materialization fails.
  """

  @behaviour Chassis.Secrets.Materializer

  alias Chassis.Secrets.{SecretLease, SecretRef}

  @impl true
  @spec materialize(SecretRef.t(), keyword()) :: {:ok, SecretLease.t()} | {:error, term()}
  def materialize(ref, opts \\ [])

  def materialize(%SecretRef{backend: :env, key: env_var} = ref, opts) do
    with {:ok, _consumer_ref} <- SecretLease.fetch_consumer(opts),
         {:ok, material} <- fetch_env(env_var) do
      SecretLease.new(ref, material, opts)
    end
  end

  def materialize(%SecretRef{backend: backend}, _opts),
    do: {:error, {:unsupported_backend, backend}}

  def materialize(_ref, _opts), do: {:error, {:invalid_secret_ref, :expected_secret_ref}}

  @impl true
  @spec revoke(SecretLease.t()) :: :ok
  def revoke(%SecretLease{}), do: :ok

  defp fetch_env(env_var) do
    case System.get_env(env_var) do
      nil -> {:error, {:env_var_unset, env_var}}
      value -> {:ok, value}
    end
  end
end
