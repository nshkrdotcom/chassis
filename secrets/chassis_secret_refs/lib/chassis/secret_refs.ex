defmodule Chassis.Secrets.SecretRef do
  @moduledoc "Opaque secret reference."
  @enforce_keys [:secret_ref]
  defstruct [:secret_ref, :backend, :version_ref, :purpose]

  @type t :: %__MODULE__{
          secret_ref: String.t(),
          backend: atom() | nil,
          version_ref: String.t() | nil,
          purpose: atom() | nil
        }
end

defmodule Chassis.Secrets.SecretLease do
  @moduledoc "In-memory secret lease. Inspect never reveals material."
  @enforce_keys [:lease_ref, :secret_ref]
  defstruct [:lease_ref, :secret_ref, :material, :expires_at, cleanup_callbacks: []]

  @type t :: %__MODULE__{
          lease_ref: String.t(),
          secret_ref: String.t(),
          material: binary() | nil,
          expires_at: DateTime.t() | nil,
          cleanup_callbacks: [function()]
        }
end

defimpl Inspect, for: Chassis.Secrets.SecretLease do
  def inspect(lease, _opts),
    do:
      "#Chassis.Secrets.SecretLease<lease_ref=#{lease.lease_ref} secret_ref=#{lease.secret_ref} material=[REDACTED]>"
end

defmodule Chassis.Secrets.MaterializationRecord do
  @moduledoc "Secret materialization receipt."
  defstruct [:secret_ref, :lease_ref, :materialized_at, :fingerprint]

  @type t :: %__MODULE__{
          secret_ref: String.t() | nil,
          lease_ref: String.t() | nil,
          materialized_at: DateTime.t() | nil,
          fingerprint: String.t() | nil
        }
end

defmodule Chassis.Secrets.Materializer do
  @moduledoc "Secret materializer behaviour."
  @callback materialize(Chassis.Secrets.SecretRef.t(), keyword()) ::
              {:ok, Chassis.Secrets.SecretLease.t()} | {:error, term()}
end

defmodule Chassis.Secrets.LeaseSupervisor do
  @moduledoc "Lease cleanup helper."
  @spec register_cleanup(Chassis.Secrets.SecretLease.t(), function()) ::
          Chassis.Secrets.SecretLease.t()
  def register_cleanup(lease, callback),
    do: %{lease | cleanup_callbacks: [callback | lease.cleanup_callbacks]}

  @spec cleanup(Chassis.Secrets.SecretLease.t()) :: :ok
  def cleanup(lease) do
    Enum.each(lease.cleanup_callbacks, & &1.())
    :ok
  end
end
