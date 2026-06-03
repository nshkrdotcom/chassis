defmodule Chassis.Secrets.Materializer.Vault do
  @moduledoc """
  Explicit future adapter for HashiCorp Vault.

  Vault belongs behind the same materializer behaviour, but no Vault client is
  active in Phase 10. The adapter therefore returns the canonical
  `not_implemented` tuple and never reports success.
  """

  @behaviour Chassis.Secrets.Materializer

  alias Chassis.Secrets.{SecretLease, SecretRef}

  @impl true
  @spec materialize(SecretRef.t(), keyword()) :: {:error, {:not_implemented, module()}}
  def materialize(ref, opts \\ [])

  def materialize(%SecretRef{}, _opts), do: {:error, {:not_implemented, __MODULE__}}
  def materialize(_ref, _opts), do: {:error, {:not_implemented, __MODULE__}}

  @impl true
  @spec revoke(SecretLease.t() | map()) :: :ok
  def revoke(_lease), do: :ok
end
