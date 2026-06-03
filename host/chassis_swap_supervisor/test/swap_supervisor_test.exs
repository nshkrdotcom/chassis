defmodule Chassis.Swap.SupervisorTest do
  use ExUnit.Case, async: false

  alias Chassis.Swap.Supervisor

  @valid_attrs %{
    candidate_ref: "cand:phase32",
    failure_batch_ref: "failure:phase32",
    patch_digest: "sha256:patch",
    artifact_digest: "sha256:candidate",
    score_matrix_ref: "score:phase32",
    regression_gate: :passed,
    authority_ref: "authority:phase32",
    operator_consent_ref: "consent:phase32",
    rollback_ref: "rollback:phase32",
    target_installation_ref: "installation:phase32",
    approved_state_volume_mounts: ["/var/lib/nshkr/state"],
    trace_id: "trace:phase32"
  }

  test "pre-flight refuses missing precondition fields" do
    attrs = Map.delete(@valid_attrs, :authority_ref)

    assert {:error, {:missing_required, :authority_ref}} =
             Supervisor.execute_swap(attrs, runtime_opts())
  end

  test "pre-flight rejects an approved mount with the wrong kind" do
    opts =
      runtime_opts(
        approved_mounts_fun: fn _app_ref, _profile_ref ->
          [%{path: "/var/lib/nshkr/state", kind: :scratch, mode: :rw}]
        end
      )

    assert {:error, {:mount_kind_mismatch, "/var/lib/nshkr/state", :scratch}} =
             Supervisor.execute_swap(@valid_attrs, opts)
  end

  test "pre-flight rejects unapproved mutable paths" do
    attrs = %{@valid_attrs | approved_state_volume_mounts: ["/tmp/not-approved"]}

    assert {:error, {:unapproved_mount_path, "/tmp/not-approved"}} =
             Supervisor.execute_swap(attrs, runtime_opts())
  end

  test "pre-flight fails closed when the approved mount provider returns invalid data" do
    opts = runtime_opts(approved_mounts_fun: fn _app_ref, _profile_ref -> nil end)

    assert {:error, {:invalid_mount_allowlist, nil}} =
             Supervisor.execute_swap(@valid_attrs, opts)
  end

  test "captures the prior artifact digest before stopping the active service" do
    {:ok, events} = Agent.start_link(fn -> [] end)

    assert {:ok, swap} =
             Supervisor.execute_swap(
               @valid_attrs,
               runtime_opts(events: events, swap_ref: "swap:capture")
             )

    assert swap.swap_ref == "swap:capture"
    assert swap.candidate_ref == "cand:phase32"
    assert swap.prior_artifact_digest == "sha256:prior"
    assert swap.previous_artifact_digest == "sha256:prior"
    assert swap.new_artifact_digest == "sha256:candidate"
    assert swap.mounts_used == [%{path: "/var/lib/nshkr/state", kind: :mutable_state, mode: :rw}]
    assert Agent.get(events, & &1) == [:current_artifact, :stop, :switch, :start]
  end

  test "replays an idempotent swap_ref without running side effects again" do
    {:ok, events} = Agent.start_link(fn -> [] end)
    {:ok, table} = Supervisor.IdempotencyTable.start_link([])
    opts = runtime_opts(events: events, idempotency_table: table, swap_ref: "swap:idempotent")

    assert {:ok, first} = Supervisor.execute_swap(@valid_attrs, opts)
    assert {:ok, second} = Supervisor.execute_swap(@valid_attrs, opts)

    assert first == second
    assert Agent.get(events, & &1) == [:current_artifact, :stop, :switch, :start]
  end

  test "rolls back with the captured prior artifact when switch fails after stop" do
    {:ok, events} = Agent.start_link(fn -> [] end)

    opts =
      runtime_opts(
        events: events,
        switch_fun: fn _ctx ->
          record(events, :switch)
          {:error, :switch_failed}
        end
      )

    assert {:error,
            {:swap_failed, :switch_failed,
             rollback:
               {:ok,
                %{
                  rollback_ref: "rollback:swap:rollback",
                  swap_ref: "swap:rollback",
                  restored_artifact_digest: "sha256:prior"
                }}}} =
             Supervisor.execute_swap(@valid_attrs, Keyword.put(opts, :swap_ref, "swap:rollback"))

    assert Agent.get(events, & &1) == [:current_artifact, :stop, :switch, :rollback]
  end

  defp runtime_opts(overrides \\ []) do
    events = Keyword.get(overrides, :events)

    defaults = [
      app_ref: "app:phase32",
      profile_ref: "prod",
      health_probe_window_ms: 90_000,
      approved_mounts_fun: fn _app_ref, _profile_ref ->
        [%{path: "/var/lib/nshkr/state", kind: :mutable_state, mode: :rw}]
      end,
      current_artifact_fun: fn _target_installation_ref ->
        record(events, :current_artifact)
        {:ok, "sha256:prior"}
      end,
      stop_fun: fn _target_installation_ref ->
        record(events, :stop)
        :ok
      end,
      switch_fun: fn _ctx ->
        record(events, :switch)
        :ok
      end,
      start_fun: fn _target_installation_ref ->
        record(events, :start)
        :ok
      end,
      rollback_fun: fn ctx ->
        record(events, :rollback)
        {:ok, ctx.restored_artifact_digest}
      end,
      now_fun: fn -> ~U[2026-06-03 12:00:00Z] end
    ]

    Keyword.merge(defaults, Keyword.drop(overrides, [:events]))
  end

  defp record(nil, _event), do: :ok
  defp record(agent, event), do: Agent.update(agent, &(&1 ++ [event]))
end
