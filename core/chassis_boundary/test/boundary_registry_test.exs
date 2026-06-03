defmodule Chassis.Boundary.RegistryTest do
  use ExUnit.Case, async: true

  alias Chassis.Boundary.Registry

  @base_protocol_refs [
    "boundary:mezzanine.chassis.materialize_deployment:v1",
    "boundary:mezzanine.chassis.rollback_deployment:v1",
    "boundary:mezzanine.chassis.inspect_host:v1",
    "boundary:mezzanine.chassis.validate_topology:v1",
    "boundary:mezzanine.chassis.drain_host:v1",
    "boundary:mezzanine.chassis.provision_host:v1",
    "boundary:appkit.chassis.read_deployment_projection:v1",
    "boundary:stacklab.chassis.run_conformance:v1"
  ]

  @adapter_keys [:beam_distribution, :external_http, :local, :unix_socket, :workflow_signal]

  test "registry contains exactly the eight Phase 12 boundary protocol specs" do
    refs = Registry.list() |> Enum.map(& &1.protocol_ref) |> Enum.sort()

    assert refs == Enum.sort(@base_protocol_refs)
  end

  test "each spec is complete and names loadable request response and error modules" do
    for spec <- Registry.list() do
      assert spec.owner in [:chassis]
      assert spec.consumer in [:mezzanine, :app_kit, :stack_lab]
      assert is_boolean(spec.mutation?)
      assert is_boolean(spec.idempotency_required?)
      assert is_boolean(spec.authority_required?)
      assert spec.trace_required? == true
      assert spec.codec == :canonical_map_v1
      assert Map.keys(spec.adapters) |> Enum.sort() == @adapter_keys
      assert spec.adapters.beam_distribution == Chassis.Boundary.BeamDistributionAdapter
      assert spec.adapters.unix_socket in [nil, Chassis.Boundary.UnixSocketAdapter]
      assert spec.adapters.workflow_signal == nil
      assert spec.adapters.external_http == nil
      assert Code.ensure_loaded?(spec.request_module)
      assert Code.ensure_loaded?(spec.response_module)
      assert Code.ensure_loaded?(spec.error_module)
    end
  end

  test "scan and conformance report concrete registry state" do
    assert {:ok, scan} = Chassis.Boundary.Scan.run([])
    assert scan.protocol_count == 8
    assert scan.protocol_refs == Enum.sort(@base_protocol_refs)
    assert scan.missing_modules == []
    assert scan.incomplete_adapter_specs == []

    assert {:ok, conformance} = Chassis.Boundary.Conformance.run([])

    assert conformance.passed == [
             "registry.base_protocol_count",
             "registry.modules_load",
             "registry.adapters_explicit",
             "codec.rejects_pid_payloads",
             "codec.digest_stability",
             "mutations.require_idempotency"
           ]

    assert conformance.failed == []
  end
end
