defmodule Chassis.Secrets.SecretRef do
  @moduledoc """
  Stable descriptor for an external secret.

  A secret ref is safe to serialize: it names where encrypted material can be
  found, but never carries the material itself.
  """

  @derive {Jason.Encoder,
           only: [:secret_ref, :tenant_ref, :backend, :path, :key, :redaction_policy_ref]}
  @enforce_keys [:secret_ref, :tenant_ref, :backend, :key]
  defstruct [
    :secret_ref,
    :tenant_ref,
    :backend,
    :path,
    :key,
    redaction_policy_ref: "redaction:secret-standard"
  ]

  @type backend :: :env | :sops | :vault
  @type t :: %__MODULE__{
          secret_ref: String.t(),
          tenant_ref: String.t(),
          backend: backend(),
          path: String.t() | nil,
          key: String.t(),
          redaction_policy_ref: String.t()
        }

  @backends [:env, :sops, :vault]
  @required [:secret_ref, :tenant_ref, :backend, :key]

  @spec new(map() | keyword()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_list(attrs) or is_map(attrs) do
    attrs = attrs |> Map.new() |> normalize_backend()

    with :ok <- require_fields(attrs),
         :ok <- validate_backend(attrs.backend),
         :ok <- validate_backend_path(attrs),
         :ok <- validate_binary(attrs, :secret_ref),
         :ok <- validate_binary(attrs, :tenant_ref),
         :ok <- validate_binary(attrs, :key) do
      {:ok,
       struct!(
         __MODULE__,
         Map.take(attrs, [
           :secret_ref,
           :tenant_ref,
           :backend,
           :path,
           :key,
           :redaction_policy_ref
         ])
       )}
    end
  end

  @spec new!(map() | keyword()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, ref} -> ref
      {:error, reason} -> raise ArgumentError, "invalid secret ref: #{inspect(reason)}"
    end
  end

  defp normalize_backend(%{backend: backend} = attrs) when is_binary(backend) do
    backend =
      case backend do
        "env" -> :env
        "sops" -> :sops
        "vault" -> :vault
        other -> other
      end

    %{attrs | backend: backend}
  end

  defp normalize_backend(attrs), do: attrs

  defp require_fields(attrs) do
    case Enum.find(@required, &blank?(Map.get(attrs, &1))) do
      nil -> :ok
      field -> {:error, {:missing_required, field}}
    end
  end

  defp validate_backend(backend) when backend in @backends, do: :ok
  defp validate_backend(backend), do: {:error, {:invalid_backend, backend}}

  defp validate_backend_path(%{backend: :env}), do: :ok

  defp validate_backend_path(attrs) do
    if blank?(Map.get(attrs, :path)) do
      {:error, {:missing_required, :path}}
    else
      validate_binary(attrs, :path)
    end
  end

  defp validate_binary(attrs, field) do
    case Map.fetch(attrs, field) do
      {:ok, value} when is_binary(value) -> :ok
      {:ok, value} -> {:error, {:invalid_field, field, value}}
      :error -> {:error, {:missing_required, field}}
    end
  end

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(_), do: false
end

defmodule Chassis.Secrets.SecretLease do
  @moduledoc """
  Short-lived in-memory lease for materialized secret bytes.

  The `:material` field is intentionally excluded from JSON encoding and
  `Inspect` output. Callers that need the raw bytes must hold the struct or
  ask `Chassis.Secrets.LeaseSupervisor` with the matching consumer ref.
  """

  @derive {Jason.Encoder, only: [:lease_ref, :secret_ref, :expires_at, :consumer_ref]}
  @enforce_keys [:lease_ref, :secret_ref, :material, :expires_at, :consumer_ref]
  defstruct [:lease_ref, :secret_ref, :material, :expires_at, :consumer_ref]

  @type t :: %__MODULE__{
          lease_ref: String.t(),
          secret_ref: String.t(),
          material: binary(),
          expires_at: DateTime.t(),
          consumer_ref: String.t()
        }

  @default_ttl_seconds 300
  @max_ttl_seconds 300

  @spec new(Chassis.Secrets.SecretRef.t(), binary(), keyword()) :: {:ok, t()} | {:error, term()}
  def new(ref, material, opts \\ [])

  def new(%Chassis.Secrets.SecretRef{} = ref, material, opts) when is_binary(material) do
    with {:ok, consumer_ref} <- fetch_consumer(opts),
         {:ok, ttl_seconds} <- ttl_seconds(opts) do
      {:ok,
       %__MODULE__{
         lease_ref: "lease:" <> random_ref(),
         secret_ref: ref.secret_ref,
         material: material,
         expires_at: DateTime.add(DateTime.utc_now(), ttl_seconds, :second),
         consumer_ref: consumer_ref
       }}
    end
  end

  def new(%Chassis.Secrets.SecretRef{}, _material, _opts),
    do: {:error, {:invalid_material, :binary_required}}

  def new(_ref, _material, _opts), do: {:error, {:invalid_secret_ref, :expected_secret_ref}}

  @spec new!(Chassis.Secrets.SecretRef.t(), binary(), keyword()) :: t()
  def new!(ref, material, opts \\ []) do
    case new(ref, material, opts) do
      {:ok, lease} -> lease
      {:error, reason} -> raise ArgumentError, "invalid secret lease: #{inspect(reason)}"
    end
  end

  @spec expired?(t()) :: boolean()
  def expired?(%__MODULE__{expires_at: expires_at}) do
    DateTime.compare(expires_at, DateTime.utc_now()) in [:lt, :eq]
  end

  @doc false
  @spec fetch_consumer(keyword()) ::
          {:ok, String.t()} | {:error, {:missing_option, :consumer_ref}}
  def fetch_consumer(opts) do
    case Keyword.get(opts, :consumer_ref) do
      consumer_ref when is_binary(consumer_ref) and consumer_ref != "" -> {:ok, consumer_ref}
      _ -> {:error, {:missing_option, :consumer_ref}}
    end
  end

  @doc false
  @spec ttl_seconds(keyword()) :: {:ok, pos_integer()} | {:error, {:invalid_ttl_seconds, term()}}
  def ttl_seconds(opts) do
    ttl = Keyword.get(opts, :ttl_seconds, @default_ttl_seconds)

    cond do
      is_integer(ttl) and ttl > 0 -> {:ok, min(ttl, @max_ttl_seconds)}
      true -> {:error, {:invalid_ttl_seconds, ttl}}
    end
  end

  defp random_ref do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end
end

defimpl Inspect, for: Chassis.Secrets.SecretLease do
  import Inspect.Algebra

  def inspect(lease, _opts) do
    concat([
      "#SecretLease<",
      lease.lease_ref,
      ", secret_ref: ",
      lease.secret_ref,
      ", consumer_ref: ",
      lease.consumer_ref,
      ", expires_at: ",
      Kernel.inspect(lease.expires_at),
      ", material: <redacted>>"
    ])
  end
end

defmodule Chassis.Secrets.MaterializationRecord do
  @moduledoc """
  Safe receipt-shaped record for a lease materialization event.

  This package-local record mirrors the 0510 shape without depending on a
  database resource. It stores only a SHA-256 hash of target paths.
  """

  @derive {Jason.Encoder,
           only: [
             :receipt_ref,
             :tenant_ref,
             :secret_ref,
             :lease_ref,
             :backend,
             :consumer_ref,
             :target_path_hash,
             :status,
             :inserted_at
           ]}
  @enforce_keys [
    :receipt_ref,
    :tenant_ref,
    :secret_ref,
    :lease_ref,
    :backend,
    :consumer_ref,
    :status,
    :inserted_at
  ]
  defstruct [
    :receipt_ref,
    :tenant_ref,
    :secret_ref,
    :lease_ref,
    :backend,
    :consumer_ref,
    :target_path_hash,
    :status,
    :inserted_at
  ]

  @type t :: %__MODULE__{
          receipt_ref: String.t(),
          tenant_ref: String.t(),
          secret_ref: String.t(),
          lease_ref: String.t(),
          backend: Chassis.Secrets.SecretRef.backend(),
          consumer_ref: String.t(),
          target_path_hash: String.t() | nil,
          status: :ok | :failed,
          inserted_at: DateTime.t()
        }

  @spec new(Chassis.Secrets.SecretRef.t(), Chassis.Secrets.SecretLease.t(), keyword()) ::
          {:ok, t()} | {:error, term()}
  def new(ref, lease, opts \\ [])

  def new(%Chassis.Secrets.SecretRef{} = ref, %Chassis.Secrets.SecretLease{} = lease, opts) do
    status = Keyword.get(opts, :status, :ok)

    if status in [:ok, :failed] do
      {:ok,
       %__MODULE__{
         receipt_ref: "receipt:materialization:" <> random_ref(),
         tenant_ref: ref.tenant_ref,
         secret_ref: ref.secret_ref,
         lease_ref: lease.lease_ref,
         backend: ref.backend,
         consumer_ref: lease.consumer_ref,
         target_path_hash: target_path_hash(Keyword.get(opts, :target_path)),
         status: status,
         inserted_at: DateTime.utc_now()
       }}
    else
      {:error, {:invalid_status, status}}
    end
  end

  def new(_ref, _lease, _opts), do: {:error, :invalid_materialization_record}

  defp target_path_hash(nil), do: nil

  defp target_path_hash(path) when is_binary(path) do
    :crypto.hash(:sha256, path) |> Base.encode16(case: :lower)
  end

  defp random_ref do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
end

defmodule Chassis.Secrets.Materializer do
  @moduledoc "Secret materialization adapter behaviour."

  alias Chassis.Secrets.{SecretLease, SecretRef}

  @callback materialize(SecretRef.t(), keyword()) :: {:ok, SecretLease.t()} | {:error, term()}
  @callback revoke(SecretLease.t()) :: :ok | {:error, term()}
end

defmodule Chassis.Secrets.LeaseSupervisor do
  @moduledoc """
  Dynamic supervisor for short-lived lease processes.

  Each child process owns a single lease and runs cleanup callbacks when the
  lease expires or is explicitly revoked.
  """

  use DynamicSupervisor

  alias Chassis.Secrets.{LeaseProcess, SecretLease}

  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts \\ []) do
    {name, _opts} = Keyword.pop(opts, :name, __MODULE__)

    case name do
      nil -> DynamicSupervisor.start_link(__MODULE__, :ok)
      _ -> DynamicSupervisor.start_link(__MODULE__, :ok, name: name)
    end
  end

  @impl true
  def init(:ok), do: DynamicSupervisor.init(strategy: :one_for_one)

  @spec register_lease(SecretLease.t(), keyword()) :: DynamicSupervisor.on_start_child()
  def register_lease(%SecretLease{} = lease, opts \\ []) do
    register_lease(__MODULE__, lease, opts)
  end

  @spec register_lease(Supervisor.supervisor(), SecretLease.t(), keyword()) ::
          DynamicSupervisor.on_start_child()
  def register_lease(supervisor, %SecretLease{} = lease, opts) do
    callbacks = Keyword.get(opts, :cleanup_callbacks, [])
    child_spec = {LeaseProcess, lease: lease, cleanup_callbacks: callbacks}
    DynamicSupervisor.start_child(supervisor, child_spec)
  end

  @spec get_material(Supervisor.supervisor(), String.t(), String.t()) ::
          {:ok, binary()} | {:error, :not_found | :unauthorized_consumer}
  def get_material(supervisor \\ __MODULE__, lease_ref, consumer_ref) do
    case find_child(supervisor, lease_ref) do
      {:ok, pid} -> LeaseProcess.get_material(pid, consumer_ref)
      :error -> {:error, :not_found}
    end
  end

  @spec revoke(String.t()) :: :ok | {:error, :not_found}
  def revoke(lease_ref), do: revoke(__MODULE__, lease_ref)

  @spec revoke(Supervisor.supervisor(), String.t()) :: :ok | {:error, :not_found}
  def revoke(supervisor, lease_ref) do
    case find_child(supervisor, lease_ref) do
      {:ok, pid} -> LeaseProcess.revoke(pid)
      :error -> {:error, :not_found}
    end
  end

  defp find_child(supervisor, lease_ref) do
    supervisor
    |> DynamicSupervisor.which_children()
    |> Enum.find_value(:error, fn
      {_, pid, _, _} when is_pid(pid) ->
        try do
          if LeaseProcess.lease_ref(pid) == lease_ref, do: {:ok, pid}, else: false
        catch
          :exit, _ -> false
        end

      _ ->
        false
    end)
  end
end

defmodule Chassis.Secrets.LeaseProcess do
  @moduledoc false

  use GenServer

  alias Chassis.Secrets.SecretLease

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{
      id: {__MODULE__, Keyword.fetch!(opts, :lease).lease_ref},
      start: {__MODULE__, :start_link, [opts]},
      restart: :temporary,
      shutdown: 5_000,
      type: :worker
    }
  end

  @spec lease_ref(pid()) :: String.t() | nil
  def lease_ref(pid), do: GenServer.call(pid, :lease_ref)

  @spec get_material(pid(), String.t()) :: {:ok, binary()} | {:error, :unauthorized_consumer}
  def get_material(pid, consumer_ref), do: GenServer.call(pid, {:get_material, consumer_ref})

  @spec revoke(pid()) :: :ok
  def revoke(pid), do: GenServer.call(pid, :revoke)

  @impl true
  def init(opts) do
    lease = Keyword.fetch!(opts, :lease)
    callbacks = Keyword.get(opts, :cleanup_callbacks, [])
    timer_ref = Process.send_after(self(), :expire, milliseconds_until(lease.expires_at))
    {:ok, %{lease: lease, callbacks: callbacks, timer_ref: timer_ref}}
  end

  @impl true
  def handle_call(:lease_ref, _from, state), do: {:reply, state.lease.lease_ref, state}

  def handle_call({:get_material, consumer_ref}, _from, state) do
    if consumer_ref == state.lease.consumer_ref do
      {:reply, {:ok, state.lease.material}, state}
    else
      {:reply, {:error, :unauthorized_consumer}, state}
    end
  end

  def handle_call(:revoke, _from, state) do
    Process.cancel_timer(state.timer_ref)
    run_callbacks(state)
    {:stop, :normal, :ok, state}
  end

  @impl true
  def handle_info(:expire, state) do
    run_callbacks(state)
    {:stop, :normal, state}
  end

  defp milliseconds_until(%DateTime{} = expires_at) do
    now = DateTime.utc_now()
    max(DateTime.to_unix(expires_at, :millisecond) - DateTime.to_unix(now, :millisecond), 0)
  end

  defp run_callbacks(%{callbacks: callbacks, lease: lease}) do
    Enum.each(callbacks, &run_callback(&1, lease))
  end

  defp run_callback(callback, %SecretLease{} = lease) when is_function(callback) do
    case Function.info(callback, :arity) do
      {:arity, 1} -> callback.(lease)
      {:arity, 0} -> callback.()
      _ -> :ok
    end
  rescue
    _ -> :ok
  end
end
