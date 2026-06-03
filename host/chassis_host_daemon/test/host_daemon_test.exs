defmodule Chassis.Host.DaemonTest do
  use ExUnit.Case, async: false

  alias Chassis.Boundary.{Envelope, Error}
  alias Chassis.Host.Daemon
  alias Chassis.Host.Daemon.{Auth, AuthCache, IdempotencyTable, Identity, Router, Socket}

  test "socket framing round-trips boundary envelopes with a 4 byte length prefix" do
    envelope = envelope()

    frame = Socket.encode_frame(envelope)
    <<byte_size::32-big, payload::binary>> = frame

    assert byte_size == byte_size(payload)
    assert {:ok, ^envelope, ""} = Socket.decode_frame(frame)
    assert {:error, :incomplete_frame} = Socket.decode_frame(binary_part(frame, 0, 5))
  end

  test "peer UID ACL rejects unauthorized socket peers" do
    assert :ok = Identity.authorize_peer(%{uid: 0}, allowed_uids: [0, 1001])
    assert :ok = Identity.authorize_peer(%{uid: 1001}, allowed_uids: [0, 1001])

    assert {:error, %Error{} = error} =
             Identity.authorize_peer(%{uid: 2002}, allowed_uids: [0, 1001])

    assert error.code == :authority_denied
    assert error.safe_message =~ "peer uid"
  end

  test "Citadel re-verification denies stale or denied authority snapshots" do
    {:ok, cache} = AuthCache.start_link(name: nil)
    envelope = envelope()

    AuthCache.put(cache, "authority:decision:allowed", :allowed,
      inserted_at: ~U[2026-06-03 10:00:00Z]
    )

    assert :ok =
             Auth.reverify(%{envelope | authority_ref: "authority:decision:allowed"},
               auth_cache: cache,
               now: ~U[2026-06-03 10:04:59Z],
               ttl_ms: 300_000
             )

    assert {:error, %Error{} = stale} =
             Auth.reverify(%{envelope | authority_ref: "authority:decision:allowed"},
               auth_cache: cache,
               now: ~U[2026-06-03 10:05:01Z],
               ttl_ms: 300_000
             )

    assert stale.code == :authority_denied
    assert stale.safe_message =~ "stale"

    AuthCache.put(cache, "authority:decision:denied", :denied,
      inserted_at: ~U[2026-06-03 10:04:00Z]
    )

    assert {:error, %Error{} = denied} =
             Auth.reverify(%{envelope | authority_ref: "authority:decision:denied"},
               auth_cache: cache,
               now: ~U[2026-06-03 10:04:30Z]
             )

    assert denied.code == :authority_denied
  end

  test "idempotency replay returns cached result and does not rerun side effects" do
    {:ok, table} = IdempotencyTable.start_link(name: nil)
    test_pid = self()

    assert {:ok, %{reply: 1}} =
             IdempotencyTable.execute(table, "idem:phase31", fn ->
               send(test_pid, :executed)
               {:ok, %{reply: 1}}
             end)

    assert_received :executed

    assert {:ok, %{reply: 1}} =
             IdempotencyTable.execute(table, "idem:phase31", fn ->
               send(test_pid, :executed_again)
               {:ok, %{reply: 2}}
             end)

    refute_received :executed_again
  end

  test "router authorizes peer and authority before dispatch and replays by idempotency key" do
    {:ok, cache} = AuthCache.start_link(name: nil)
    {:ok, table} = IdempotencyTable.start_link(name: nil)
    test_pid = self()
    envelope = envelope(idempotency_key: "idem:route:phase31")

    AuthCache.put(cache, envelope.authority_ref, :allowed, inserted_at: ~U[2026-06-03 10:00:00Z])

    handler = fn authorized ->
      send(test_pid, {:handled, authorized.envelope_ref})
      {:ok, %{state: :accepted, envelope_ref: authorized.envelope_ref}}
    end

    opts = [
      auth_cache: cache,
      idempotency_table: table,
      now: ~U[2026-06-03 10:00:30Z],
      peer: %{uid: 0},
      allowed_uids: [0],
      handlers: %{"boundary:chassis.host_daemon.swap:v1" => handler}
    ]

    assert {:ok, %{state: :accepted}} = Router.route(envelope, opts)
    assert_received {:handled, "env:phase31"}

    assert {:ok, %{state: :accepted}} = Router.route(envelope, opts)
    refute_received {:handled, "env:phase31"}

    assert {:error, %Error{} = peer_error} =
             Router.route(envelope, Keyword.put(opts, :peer, %{uid: 999}))

    assert peer_error.safe_message =~ "peer uid"
  end

  test "daemon status and systemd unit expose the required socket posture" do
    status = Daemon.status()

    assert status.state == :running
    assert status.socket_path == "/var/run/nshkr_chassis_host.sock"
    assert status.socket_mode == "0660"
    assert status.socket_owner == "nshkr_chassis_host:nshkr_chassis_host"

    unit = File.read!(Path.expand("../priv/systemd/nshkr-chassis-host.service", __DIR__))
    assert unit =~ "User=nshkr_chassis_host"
    assert unit =~ "Group=nshkr_chassis_host"
    assert unit =~ "Restart=on-failure"
  end

  defp envelope(overrides \\ []) do
    %{
      protocol_ref: "boundary:chassis.host_daemon.swap:v1",
      envelope_ref: "env:phase31",
      tenant_ref: "tenant:dev",
      installation_ref: "installation:prod",
      actor_ref: "user:operator",
      system_actor_ref: "system:chassis",
      authority_ref: "authority:decision:phase31",
      idempotency_key: "idem:phase31",
      trace_id: "trace:phase31",
      correlation_id: "corr:phase31",
      issued_at: ~U[2026-06-03 10:00:00Z],
      status: :request,
      payload: %{
        intent_ref: "authority:chassis:host_daemon:swap",
        candidate_ref: "cand:phase31",
        operator_consent_ref: "operator-consent:phase31"
      }
    }
    |> Map.merge(Map.new(overrides))
    |> Envelope.new!()
  end
end
