defmodule Chassis.Trial.IsolationProfile do
  @moduledoc "Trial isolation profile with BEAM identity, cookie, ports, and mount policy."

  defstruct [
    :candidate_ref,
    :beam_node_name,
    :cookie_ref,
    :port_range,
    :created_at,
    state_volume_mounts: []
  ]

  @type t :: %__MODULE__{}

  @spec default(String.t()) :: t()
  def default(candidate_ref) when is_binary(candidate_ref) do
    unique = System.unique_integer([:positive, :monotonic])
    base_port = 12_000 + rem(unique * 100, 40_000)
    safe = safe_ref(candidate_ref)

    %__MODULE__{
      candidate_ref: candidate_ref,
      beam_node_name: "trial-#{safe}-#{unique}@127.0.0.1",
      cookie_ref: "cookie:" <> digest({candidate_ref, unique, :cookie}),
      port_range: base_port..(base_port + 99),
      created_at: DateTime.utc_now()
    }
  end

  @spec validate_mounts(t(), keyword()) :: :ok | {:error, :forbidden_production_state_in_trial}
  def validate_mounts(%__MODULE__{}, opts) do
    approved =
      opts |> Keyword.get(:approved_state_volume_mounts, []) |> Enum.map(&normalize_path/1)

    requested = opts |> Keyword.get(:state_volume_mounts, []) |> Enum.map(&normalize_path/1)

    if Enum.any?(requested, fn mount -> Enum.any?(approved, &overlap?(mount, &1)) end) do
      {:error, :forbidden_production_state_in_trial}
    else
      :ok
    end
  end

  defp overlap?(a, b),
    do: String.starts_with?(a, b <> "/") or a == b or String.starts_with?(b, a <> "/")

  defp normalize_path(path), do: path |> Path.expand() |> String.trim_trailing("/")
  defp safe_ref(ref), do: Regex.replace(~r/[^A-Za-z0-9_.-]/, ref, "_")

  defp digest(value) do
    :crypto.hash(:sha256, :erlang.term_to_binary(value))
    |> Base.encode16(case: :lower)
    |> binary_part(0, 24)
  end
end

defmodule Chassis.Trial.Runtime do
  @moduledoc "Trial runtime facade."

  @behaviour Chassis.Evolution.TrialProvider

  alias Chassis.Evolution.DTO.CandidatePatch
  alias Chassis.Trial.IsolationProfile

  @providers [:fixture, :container, :systemd, :ssh]

  @spec provision(map(), keyword()) :: {:ok, map()} | {:error, term()}
  def provision(attrs, opts \\ []) do
    kind = Keyword.get(opts, :kind, :fixture)
    patch = candidate_patch_from_attrs(attrs)
    provision_trial(kind, patch, opts)
  end

  @impl true
  def provision_trial(kind, %CandidatePatch{} = patch, opts) when kind in @providers do
    profile = IsolationProfile.default(patch.candidate_ref)

    with :ok <- IsolationProfile.validate_mounts(profile, opts) do
      provider_module(kind).provision(patch, Keyword.put(opts, :isolation_profile, profile))
    end
  end

  def provision_trial(kind, _patch, _opts), do: {:error, {:unknown_trial_provider, kind}}

  @impl true
  def teardown_trial(trial_ref, opts \\ []) when is_binary(trial_ref) do
    Chassis.Trial.Supervisor.stop_trial(
      Keyword.get(opts, :trial_supervisor, Chassis.Trial.Supervisor),
      trial_ref
    )
  end

  @spec jsonable_trial(map()) :: map()
  def jsonable_trial(trial) do
    %{
      trial_ref: trial.trial_ref,
      trial_node_ref: trial.trial_node_ref,
      candidate_ref: trial.candidate_ref,
      provider: Atom.to_string(trial.provider),
      status: Atom.to_string(Map.get(trial, :status, :running)),
      isolation: %{
        beam_node_name: trial.isolation.beam_node_name,
        cookie_ref: trial.isolation.cookie_ref,
        port_range: [trial.isolation.port_range.first, trial.isolation.port_range.last]
      }
    }
  end

  defp candidate_patch_from_attrs(attrs) do
    CandidatePatch.new!(%{
      candidate_ref: Map.get(attrs, :candidate_ref, "cand:dev:smoke"),
      base_release_ref: Map.get(attrs, :base_release_ref, "release:base"),
      patch_digest: Map.get(attrs, :patch_digest, "sha256:patch"),
      diff_ref: Map.get(attrs, :diff_ref) || Map.get(attrs, :diff_path, "diff:fixture"),
      failure_batch_ref: Map.get(attrs, :failure_batch_ref, "failure_batch:phase26"),
      created_at: DateTime.utc_now()
    })
  end

  defp provider_module(:fixture), do: Chassis.Trial.Provider.Fixture
  defp provider_module(:container), do: Chassis.Trial.Provider.Container
  defp provider_module(:systemd), do: Chassis.Trial.Provider.Systemd
  defp provider_module(:ssh), do: Chassis.Trial.Provider.SSH
end

for {provider, kind} <- [
      {Fixture, :fixture},
      {Container, :container},
      {Systemd, :systemd},
      {SSH, :ssh}
    ] do
  defmodule Module.concat(Chassis.Trial.Provider, provider) do
    @moduledoc "Phase 26 isolated trial provider."
    @kind kind

    @spec provision(Chassis.Evolution.DTO.CandidatePatch.t(), keyword()) ::
            {:ok, map()} | {:error, term()}
    def provision(%Chassis.Evolution.DTO.CandidatePatch{} = patch, opts \\ []) do
      isolation = Keyword.fetch!(opts, :isolation_profile)
      supervisor = Keyword.get(opts, :trial_supervisor, Chassis.Trial.Supervisor)

      attrs = %{
        candidate_ref: patch.candidate_ref,
        diff_ref: patch.diff_ref,
        provider: @kind,
        isolation: isolation,
        trial_node_ref: isolation.beam_node_name,
        trial_ref:
          "trial:#{patch.candidate_ref}:#{System.unique_integer([:positive, :monotonic])}"
      }

      Chassis.Trial.Supervisor.start_trial(supervisor, attrs)
    end

    @spec teardown(String.t(), keyword()) :: {:ok, map()} | {:error, :not_found}
    def teardown(trial_ref, opts \\ []) do
      supervisor = Keyword.get(opts, :trial_supervisor, Chassis.Trial.Supervisor)
      Chassis.Trial.Supervisor.stop_trial(supervisor, trial_ref)
    end
  end
end
