defmodule Chassis.Trial.Supervisor do
  @moduledoc "Trial build/start supervisor facade with an in-memory lifecycle store."

  @type server :: pid() | atom()

  @spec start_link(keyword()) :: Agent.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)

    case name do
      nil -> Agent.start_link(fn -> %{trials: %{}} end, opts)
      name -> start_named(name, opts)
    end
  end

  @spec build_candidate(map()) :: {:ok, map()}
  def build_candidate(attrs), do: build_candidate(default_server(), attrs)

  @spec build_candidate(server(), map()) :: {:ok, map()}
  def build_candidate(_server, attrs) when is_map(attrs) do
    digest = sha256(Map.take(attrs, [:candidate_ref, :diff_ref, :build_strategy]))

    {:ok,
     attrs
     |> Map.put(:candidate_image_digest, "sha256:#{digest}")
     |> Map.put_new(:build_strategy, :fixture)
     |> Map.put_new(:built_at, DateTime.utc_now())}
  end

  @spec start_trial(map()) :: {:ok, map()}
  def start_trial(attrs), do: start_trial(default_server(), attrs)

  @spec start_trial(server(), map()) :: {:ok, map()}
  def start_trial(server, attrs) when is_map(attrs) do
    server = ensure_server(server)
    ref = Map.get(attrs, :trial_ref) || trial_ref(Map.fetch!(attrs, :candidate_ref))

    trial =
      attrs
      |> Map.put(:trial_ref, ref)
      |> Map.put_new(:started_at, DateTime.utc_now())
      |> Map.put_new(:status, :running)

    Agent.update(server, &put_in(&1.trials[ref], trial))
    {:ok, trial}
  end

  @spec stop_trial(String.t()) :: {:ok, map()} | {:error, :not_found}
  def stop_trial(trial_ref), do: stop_trial(default_server(), trial_ref)

  @spec stop_trial(server(), String.t()) :: {:ok, map()} | {:error, :not_found}
  def stop_trial(server, trial_ref) when is_binary(trial_ref) do
    server = ensure_server(server)

    Agent.get_and_update(server, fn state ->
      case Map.fetch(state.trials, trial_ref) do
        {:ok, trial} ->
          stopped =
            trial
            |> Map.put(:status, :stopped)
            |> Map.put(:stopped?, true)
            |> Map.put(:torn_down?, true)
            |> Map.put(:stopped_at, DateTime.utc_now())

          {{:ok, stopped}, update_in(state.trials, &Map.delete(&1, trial_ref))}

        :error ->
          {{:error, :not_found}, state}
      end
    end)
  end

  @spec list_trials(server()) :: [map()]
  def list_trials(server \\ default_server()) do
    server = ensure_server(server)

    server
    |> Agent.get(&Map.values(&1.trials))
    |> Enum.sort_by(& &1.started_at, {:desc, DateTime})
  end

  defp start_named(name, opts) do
    case Agent.start_link(fn -> %{trials: %{}} end, Keyword.put(opts, :name, name)) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      other -> other
    end
  end

  defp default_server do
    case Process.whereis(__MODULE__) do
      nil ->
        {:ok, pid} = start_link()
        pid

      pid ->
        pid
    end
  end

  defp ensure_server(server) when is_pid(server), do: server

  defp ensure_server(server) when is_atom(server) do
    case Process.whereis(server) do
      nil ->
        {:ok, pid} = start_link(name: server)
        pid

      pid ->
        pid
    end
  end

  defp trial_ref(candidate_ref) do
    "trial:#{candidate_ref}:#{System.unique_integer([:positive, :monotonic])}"
  end

  defp sha256(value) do
    :crypto.hash(:sha256, :erlang.term_to_binary(value))
    |> Base.encode16(case: :lower)
    |> binary_part(0, 24)
  end
end
