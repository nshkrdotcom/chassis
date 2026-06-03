defmodule Chassis.Health.ProbeTest do
  use ExUnit.Case, async: false

  alias Chassis.Health.Probe

  @checks [
    :http_health,
    :beam_alive,
    :mesh_connectivity,
    :appkit_readback,
    :mezzanine_heartbeat,
    :citadel_smoke,
    :state_heartbeat,
    :model_runtime_health
  ]

  setup do
    if Code.ensure_loaded?(Chassis.Metrics.Backend.Test) do
      Chassis.Metrics.Backend.Test.reset()
    end

    :ok
  end

  test "default policy uses 90s window, 5s interval, and three consecutive successes" do
    assert %{
             window_ms: 90_000,
             interval_ms: 5_000,
             consecutive_required: 3,
             rollback_on_failure?: true,
             checks: @checks
           } = Probe.default_policy()
  end

  test "successful probe commits after three consecutive successful ticks" do
    {:ok, events} = Agent.start_link(fn -> [] end)

    assert {:ok,
            %{
              swap_ref: "swap:success",
              outcome: :committed,
              consecutive_successes: 3,
              ticks: 3,
              checks: @checks
            }} =
             Probe.run(%{swap_ref: "swap:success"},
               check_fun: check_recorder(events, :ok),
               rollback_fun: rollback_recorder(events)
             )

    refute Enum.any?(Agent.get(events, & &1), &match?({:rollback, _}, &1))
    assert Enum.count(Agent.get(events, & &1), &match?({:check, :http_health}, &1)) == 3
  end

  test "forced check failure rolls back immediately" do
    {:ok, events} = Agent.start_link(fn -> [] end)

    check_fun = fn
      :http_health, _context ->
        record(events, {:check, :http_health})
        {:error, :http_500}

      check, _context ->
        record(events, {:check, check})
        :ok
    end

    assert {:ok,
            %{
              swap_ref: "swap:failure",
              outcome: :rolled_back,
              reason: {:probe_failed, :http_health, :http_500},
              rollback: {:ok, %{rollback_ref: "rollback:swap:failure"}}
            }} =
             Probe.run(%{swap_ref: "swap:failure"},
               check_fun: check_fun,
               rollback_fun: rollback_recorder(events)
             )

    assert Agent.get(events, & &1) == [
             {:check, :http_health},
             {:rollback, "swap:failure"}
           ]
  end

  test "timeout rolls back when the window cannot satisfy the consecutive success policy" do
    {:ok, events} = Agent.start_link(fn -> [] end)

    assert {:ok,
            %{
              swap_ref: "swap:timeout",
              outcome: :rolled_back,
              reason: :probe_timeout,
              rollback: {:ok, %{rollback_ref: "rollback:swap:timeout"}},
              ticks: 2
            }} =
             Probe.run(%{swap_ref: "swap:timeout"},
               policy: %{window_ms: 10_000, interval_ms: 5_000, consecutive_required: 3},
               check_fun: check_recorder(events, :ok),
               rollback_fun: rollback_recorder(events)
             )

    assert Enum.any?(Agent.get(events, & &1), &match?({:rollback, "swap:timeout"}, &1))
  end

  test "rollback double fault emits a critical health signal" do
    {:ok, events} = Agent.start_link(fn -> [] end)

    assert {:ok,
            %{
              outcome: :rolled_back_failed,
              rollback: {:error, :restore_failed},
              health_signal: %{status: :critical, reason: :rollback_failed}
            }} =
             Probe.run(%{swap_ref: "swap:double-fault", service_ref: "service:demo"},
               check_fun: check_recorder(events, {:error, :beam_down}),
               rollback_fun: fn swap_ref, _opts ->
                 record(events, {:rollback, swap_ref})
                 {:error, :restore_failed}
               end,
               metrics_backend: Chassis.Metrics.Backend.Test
             )

    assert [signal] = Chassis.Metrics.Backend.Test.list()
    assert signal.status == :critical
    assert signal.reason == :rollback_failed
    assert signal.metadata.severity == :critical
    assert signal.metadata.kind == :rollback_failed
    assert signal.metadata.swap_ref == "swap:double-fault"
  end

  defp check_recorder(events, result) do
    fn check, _context ->
      record(events, {:check, check})
      result
    end
  end

  defp rollback_recorder(events) do
    fn swap_ref, _opts ->
      record(events, {:rollback, swap_ref})

      {:ok,
       %{
         rollback_ref: "rollback:#{swap_ref}",
         swap_ref: swap_ref,
         restored_artifact_digest: "sha256:prior"
       }}
    end
  end

  defp record(agent, event), do: Agent.update(agent, &(&1 ++ [event]))
end
