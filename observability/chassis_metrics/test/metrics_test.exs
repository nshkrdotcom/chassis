defmodule Chassis.MetricsTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Chassis.Contracts.IsolationProfile
  alias Chassis.Metrics
  alias Chassis.Metrics.Backend
  alias NSHKR.Observability.{HealthSignal, Metric}

  setup do
    Backend.Test.reset()
    on_exit(fn -> Backend.Test.reset() end)
    :ok
  end

  test "metric catalogue exposes exactly the 12 OTel-compatible metrics" do
    assert MapSet.new(Metrics.metric_names()) ==
             MapSet.new([
               "chassis.deployment.count_total",
               "chassis.deployment.duration_ms",
               "chassis.provisioning.step_count",
               "chassis.ssh.session_duration_ms",
               "chassis.mesh.node_count",
               "chassis.mesh.health_failures_total",
               "chassis.secret.lease_count",
               "chassis.secret.lease_expiry_total",
               "chassis.rollback.count_total",
               "chassis.authority.denied_total",
               "chassis.boundary.call_duration_ms",
               "chassis.topology.validation_failures_total"
             ])

    assert %{kind: :counter, labels: [:profile, :env, :status, :tenant_ref]} =
             Metrics.metric_spec(:chassis_deployment_count_total)
  end

  test "counter, gauge, and histogram helpers emit real Metric structs to the Test backend" do
    isolation = %IsolationProfile{observability_isolation: :shared_redacted}

    assert :ok =
             Metrics.incr(
               :chassis_deployment_count_total,
               %{profile: "profile:monolith", env: :dev, status: :ok, tenant_ref: "tenant:acme"},
               backend: Backend.Test,
               trace_id: "trace:phase15:counter",
               isolation_profile: isolation
             )

    assert :ok =
             Metrics.gauge(:chassis_mesh_node_count, 3, %{cluster_ref: "cluster:dev"},
               backend: Backend.Test
             )

    assert :ok =
             Metrics.observe(
               :chassis_boundary_call_duration_ms,
               42,
               %{protocol_ref: "boundary:test", adapter: "local", status: :ok},
               backend: Backend.Test
             )

    assert [
             %Metric{name: "chassis.deployment.count_total"} = counter,
             %Metric{name: "chassis.mesh.node_count"} = gauge,
             %Metric{name: "chassis.boundary.call_duration_ms"} = histogram
           ] = Backend.Test.list()

    assert counter.kind == :counter
    assert counter.value == 1
    assert counter.trace_id == "trace:phase15:counter"
    assert counter.labels["tenant_ref"] =~ ~r/^tenant:sha256:[0-9a-f]{16}$/
    assert counter.labels["tenant_partition"] == "shared_redacted"
    assert gauge.kind == :gauge
    assert gauge.value == 3
    assert histogram.kind == :histogram
    assert histogram.unit == :milliseconds
  end

  test "invalid metric atoms and wrong helpers fail closed without side effects" do
    assert {:error, {:unknown_metric, :not_a_chassis_metric}} =
             Metrics.incr(:not_a_chassis_metric, %{}, backend: Backend.Test)

    assert {:error, {:wrong_metric_kind, :gauge, :counter}} =
             Metrics.incr(:chassis_mesh_node_count, %{}, backend: Backend.Test)

    assert Backend.Test.list() == []
  end

  test "emit_health_signal builds and emits a HealthSignal with required attrs" do
    assert :ok =
             Metrics.emit_health_signal(
               %{
                 service_ref: "svc:chassis-mesh-node",
                 status: :unhealthy,
                 reason: :latency_slo_breach,
                 observed_value: 2_500,
                 threshold: 2_000,
                 unit: :milliseconds,
                 trace_id: "trace:phase15:health"
               },
               backend: Backend.Test
             )

    assert [%HealthSignal{} = signal] = Backend.Test.list()
    assert signal.signal_ref =~ ~r/^health-signal:[0-9a-f]{16}$/
    assert signal.service_ref == "svc:chassis-mesh-node"
    assert signal.status == :unhealthy
    assert signal.reason == :latency_slo_breach
    assert signal.trace_id == "trace:phase15:health"

    Backend.Test.reset()

    assert {:error, {:missing_required_health_signal_attr, :service_ref}} =
             Metrics.emit_health_signal(%{status: :healthy}, backend: Backend.Test)

    assert Backend.Test.list() == []
  end

  test "File backend writes JSONL and preserves tenant partitioning without raw tenant leakage" do
    path =
      Path.join(System.tmp_dir!(), "chassis-metrics-phase15-#{System.unique_integer()}.jsonl")

    on_exit(fn -> File.rm(path) end)

    assert :ok =
             Metrics.incr(
               :chassis_authority_denied_total,
               %{operation: "deploy", tenant_ref: "tenant:secret-customer"},
               backend: {Backend.File, path: path},
               isolation_profile: %IsolationProfile{observability_isolation: :shared_redacted}
             )

    assert {:ok, body} = File.read(path)
    assert [line] = String.split(String.trim(body), "\n")
    assert {:ok, decoded} = Jason.decode(line)
    assert decoded["name"] == "chassis.authority.denied_total"
    assert decoded["kind"] == "counter"
    assert decoded["labels"]["tenant_ref"] =~ ~r/^tenant:sha256:[0-9a-f]{16}$/
    refute body =~ "tenant:secret-customer"
  end

  test "OTel backend emits telemetry events and Console backend writes debug output" do
    handler_id = :"phase15-metrics-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach(
        handler_id,
        [:chassis, :metrics, :metric],
        &__MODULE__.handle_telemetry/4,
        self()
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    assert :ok =
             Metrics.gauge(:chassis_secret_lease_count, 4, %{backend: "sops"},
               backend: Backend.OTel
             )

    assert_receive {:telemetry_metric, [:chassis, :metrics, :metric], %{value: 4}, metadata}
    assert metadata.name == "chassis.secret.lease_count"
    assert metadata.kind == :gauge

    output =
      capture_io(fn ->
        assert :ok =
                 Metrics.observe(:chassis_ssh_session_duration_ms, 150, %{host_ref: "host:vps-1"},
                   backend: Backend.Console
                 )
      end)

    assert output =~ "chassis.ssh.session_duration_ms"
  end

  test "every catalogue metric can be emitted with fixture labels" do
    for {metric_atom, spec} <- Metrics.metric_catalogue() do
      assert :ok = emit_fixture(metric_atom, spec)
    end

    emitted_names = Backend.Test.list() |> Enum.map(& &1.name) |> MapSet.new()
    assert emitted_names == MapSet.new(Metrics.metric_names())
  end

  defp emit_fixture(metric_atom, %{kind: :counter}) do
    Metrics.incr(metric_atom, fixture_labels(metric_atom), backend: Backend.Test)
  end

  defp emit_fixture(metric_atom, %{kind: :gauge}) do
    Metrics.gauge(metric_atom, 2, fixture_labels(metric_atom), backend: Backend.Test)
  end

  defp emit_fixture(metric_atom, %{kind: :histogram}) do
    Metrics.observe(metric_atom, 25, fixture_labels(metric_atom), backend: Backend.Test)
  end

  defp fixture_labels(:chassis_deployment_count_total),
    do: %{profile: "profile:monolith", env: :dev, status: :ok, tenant_ref: "tenant:acme"}

  defp fixture_labels(:chassis_deployment_duration_ms),
    do: %{profile: "profile:monolith", env: :dev}

  defp fixture_labels(:chassis_provisioning_step_count), do: %{phase: "install", status: :ok}
  defp fixture_labels(:chassis_ssh_session_duration_ms), do: %{host_ref: "host:vps-1"}
  defp fixture_labels(:chassis_mesh_node_count), do: %{cluster_ref: "cluster:dev"}

  defp fixture_labels(:chassis_mesh_health_failures_total),
    do: %{node_ref: "node:app", reason: "down"}

  defp fixture_labels(:chassis_secret_lease_count), do: %{backend: "sops"}
  defp fixture_labels(:chassis_secret_lease_expiry_total), do: %{backend: "sops", reason: "ttl"}

  defp fixture_labels(:chassis_rollback_count_total),
    do: %{trigger: "operator", tenant_ref: "tenant:acme"}

  defp fixture_labels(:chassis_authority_denied_total),
    do: %{operation: "deploy", tenant_ref: "tenant:acme"}

  defp fixture_labels(:chassis_boundary_call_duration_ms),
    do: %{protocol_ref: "boundary:test", adapter: "local", status: :ok}

  defp fixture_labels(:chassis_topology_validation_failures_total),
    do: %{tenant_ref: "tenant:acme", error_code: "capacity"}

  def handle_telemetry(event, measurements, metadata, test_pid) do
    send(test_pid, {:telemetry_metric, event, measurements, metadata})
  end
end
