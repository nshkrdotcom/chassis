defmodule Chassis.AITrace.BridgeTest do
  use ExUnit.Case, async: false

  alias Chassis.AITrace.Bridge

  defmodule TestExporter do
    @behaviour AITrace.Exporter

    @impl true
    def init(opts), do: {:ok, opts}

    @impl true
    def export(trace, %{test_pid: test_pid} = state) do
      send(test_pid, {:exported_trace, trace})
      {:ok, state}
    end

    @impl true
    def shutdown(_state), do: :ok
  end

  setup do
    old_bridge_exporters = Application.get_env(:chassis_aitrace_bridge, :exporters)
    old_otel_exporters = Application.get_env(:chassis_aitrace_bridge, :otel_exporters)
    old_aitrace_exporters = Application.get_env(:aitrace, :exporters)

    on_exit(fn ->
      restore_env(:chassis_aitrace_bridge, :exporters, old_bridge_exporters)
      restore_env(:chassis_aitrace_bridge, :otel_exporters, old_otel_exporters)
      restore_env(:aitrace, :exporters, old_aitrace_exporters)
    end)

    :ok
  end

  test "span catalogue exposes exactly the required Phase 14 deployment spans" do
    assert MapSet.new(Bridge.span_names()) ==
             MapSet.new([
               "chassis.deployment.accepted",
               "chassis.adapter.selected",
               "chassis.provisioning.started",
               "chassis.provisioning.completed",
               "chassis.mesh.joined",
               "chassis.health.checked",
               "chassis.health.unhealthy",
               "chassis.receipt.emitted",
               "chassis.rollback.triggered",
               "chassis.deployment.denied",
               "chassis.secret.materialized",
               "chassis.secret.revoked",
               "chassis.key.rotated"
             ])

    assert [:tenant_ref, :installation_ref, :app_atom, :profile_ref, :environment, :git_sha] =
             Bridge.required_attributes("chassis.deployment.accepted")
  end

  test "emit_span exports a completed AITrace trace through configured exporters" do
    attrs =
      fixture_attrs("chassis.deployment.accepted")
      |> Map.merge(%{
        ip_address: "192.0.2.44",
        node_ref: :app@prod_host,
        private_key: "-----BEGIN PRIVATE KEY-----\nsecret",
        token: "raw-token",
        ssh_user: "root"
      })

    assert {:ok, "span:" <> span_id} =
             Bridge.emit_span("chassis.deployment.accepted", attrs,
               trace_id: "trace:phase14:span",
               exporters: [{TestExporter, test_pid: self()}]
             )

    assert_receive {:exported_trace, %AITrace.Trace{} = trace}
    assert trace.trace_id == "trace:phase14:span"
    assert [%AITrace.Span{} = span] = trace.spans
    assert span.span_id == span_id
    assert span.end_time != nil
    assert span.name == "chassis.deployment.accepted"
    assert span.status == :ok

    assert span.attributes["tenant_ref"] == "tenant:acme"
    assert span.attributes["ip_address"] =~ ~r/^ip:[0-9a-f]{16}$/
    assert span.attributes["node_ref"] =~ ~r/^node:[0-9a-f]{16}$/
    refute encoded(trace) =~ "192.0.2.44"
    refute encoded(trace) =~ "PRIVATE KEY"
    refute encoded(trace) =~ "raw-token"
    refute Map.has_key?(span.attributes, "ssh_user")

    assert %{"schema_version" => "aitrace.export_bounds.v1"} =
             span.attributes["_aitrace_export_overflow"]
  end

  test "emit_event attaches a bounded event to an exported trace" do
    assert {:ok, "event:" <> _event_ref} =
             Bridge.emit_event(
               "chassis.health.unhealthy",
               Map.merge(fixture_attrs("chassis.health.unhealthy"), %{
                 ip_address: "203.0.113.5",
                 secret: "raw-secret"
               }),
               trace_id: "trace:phase14:event",
               exporters: [{TestExporter, test_pid: self()}]
             )

    assert_receive {:exported_trace, %AITrace.Trace{} = trace}
    assert [%AITrace.Span{} = span] = trace.spans
    assert [%AITrace.Event{} = event] = span.events
    assert span.name == "chassis.aitrace.event"
    assert event.name == "chassis.health.unhealthy"
    assert event.attributes["ip_address"] =~ ~r/^ip:[0-9a-f]{16}$/
    refute encoded(trace) =~ "203.0.113.5"
    refute encoded(trace) =~ "raw-secret"
  end

  test "missing required attributes fail closed without exporter side effects" do
    attrs = Map.delete(fixture_attrs("chassis.deployment.accepted"), :git_sha)

    assert {:error, {:missing_required_attributes, ["git_sha"]}} =
             Bridge.emit_span("chassis.deployment.accepted", attrs,
               trace_id: "trace:phase14:missing",
               exporters: [{TestExporter, test_pid: self()}]
             )

    refute_received {:exported_trace, _trace}
  end

  test "file URI exporter writes JSONL records with bounded attributes" do
    path =
      Path.join(System.tmp_dir!(), "chassis-aitrace-phase14-#{System.unique_integer()}.jsonl")

    on_exit(fn -> File.rm(path) end)

    assert {:ok, "span:" <> _} =
             Bridge.emit_span(
               "chassis.adapter.selected",
               Map.merge(fixture_attrs("chassis.adapter.selected"), %{
                 ip_address: "198.51.100.8",
                 password: "raw-password"
               }),
               trace_id: "trace:phase14:file",
               export_url: "file://" <> path
             )

    assert {:ok, body} = File.read(path)
    assert [line] = String.split(String.trim(body), "\n")
    assert {:ok, decoded} = Jason.decode(line)
    assert decoded["name"] == "chassis.adapter.selected"
    assert decoded["trace_id"] == "trace:phase14:file"
    assert decoded["kind"] == "span"
    assert decoded["attributes"]["ip_address"] =~ ~r/^ip:[0-9a-f]{16}$/
    refute body =~ "198.51.100.8"
    refute body =~ "raw-password"
  end

  test "export config defaults to AITrace file in dev and configured exporters in prod" do
    assert [{AITrace.Exporter.File, dev_opts}] = Bridge.default_exporters(:dev)
    assert dev_opts[:directory] == "/tmp/chassis_aitrace"

    Application.put_env(:chassis_aitrace_bridge, :otel_exporters, [
      {TestExporter, test_pid: self(), backend: :otel_compatible}
    ])

    assert [{TestExporter, prod_opts}] = Bridge.default_exporters(:prod)
    assert prod_opts[:backend] == :otel_compatible
  end

  test "all catalogue names can be emitted with their required attributes" do
    for name <- Bridge.span_names() do
      assert {:ok, _ref} =
               Bridge.emit_span(name, fixture_attrs(name),
                 trace_id: "trace:phase14:catalogue",
                 exporters: [{TestExporter, test_pid: self()}]
               )

      assert_receive {:exported_trace, %AITrace.Trace{} = trace}
      assert [%{name: ^name}] = trace.spans
    end
  end

  defp fixture_attrs("chassis.deployment.accepted") do
    %{
      tenant_ref: "tenant:acme",
      installation_ref: "installation:acme:demo",
      app_atom: :demo,
      profile_ref: "profile:monolith",
      environment: :dev,
      git_sha: "abcdef123456"
    }
  end

  defp fixture_attrs("chassis.adapter.selected") do
    %{
      profile_ref: "profile:monolith",
      environment: :dev,
      provisioning_adapter: "ssh",
      mesh_adapter: "beam-distribution",
      secrets_materializer: "sops"
    }
  end

  defp fixture_attrs("chassis.provisioning.started") do
    %{host_ref: "host:vps-1", env_config_ref: "env:dev", phase: "install"}
  end

  defp fixture_attrs("chassis.provisioning.completed") do
    %{host_ref: "host:vps-1", phase: "install", status: "ok", step_count: 7}
  end

  defp fixture_attrs("chassis.mesh.joined") do
    %{node_ref: "node:app", cluster_ref: "cluster:dev"}
  end

  defp fixture_attrs("chassis.health.checked") do
    %{node_ref: "node:app", status: "healthy"}
  end

  defp fixture_attrs("chassis.health.unhealthy") do
    %{node_ref: "node:app", status: "unhealthy", reason: "latency_slo_breach"}
  end

  defp fixture_attrs("chassis.receipt.emitted") do
    %{receipt_ref: "receipt:deploy:1", tenant_ref: "tenant:acme", app_atom: :demo, status: "ok"}
  end

  defp fixture_attrs("chassis.rollback.triggered") do
    %{previous_receipt_ref: "receipt:deploy:0", trigger: "operator", tenant_ref: "tenant:acme"}
  end

  defp fixture_attrs("chassis.deployment.denied") do
    %{
      tenant_ref: "tenant:acme",
      installation_ref: "installation:acme:demo",
      protocol_ref: "boundary:mezzanine.chassis.materialize_deployment:v1",
      code: "authority_denied"
    }
  end

  defp fixture_attrs("chassis.secret.materialized") do
    %{secret_ref: "secret:deploy-key", backend: "sops", consumer_ref: "host:vps-1"}
  end

  defp fixture_attrs("chassis.secret.revoked") do
    %{lease_ref: "lease:1234", consumer_ref: "host:vps-1"}
  end

  defp fixture_attrs("chassis.key.rotated") do
    %{key_name: "deploy", previous_version: "v1", new_version: "v2"}
  end

  defp encoded(value) do
    inspect(value, limit: :infinity, printable_limit: :infinity)
  end

  defp restore_env(app, key, nil), do: Application.delete_env(app, key)
  defp restore_env(app, key, value), do: Application.put_env(app, key, value)
end
