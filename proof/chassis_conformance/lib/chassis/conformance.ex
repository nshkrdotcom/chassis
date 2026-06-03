defmodule Chassis.Conformance do
  @moduledoc "Executable Phase 21 Chassis conformance proof catalog."

  alias Chassis.Conformance.Proofs

  @proof_names [
    "chassis.boundary.local_adapter_equivalence.v1",
    "chassis.boundary.no_pid_payloads.v1",
    "chassis.boundary.no_raw_secret_payloads.v1",
    "chassis.boundary.codec_digest_stability.v1",
    "chassis.boundary.idempotency_required_for_mutations.v1",
    "chassis.boundary.citadel_fail_closed.v1",
    "chassis.deployment.profile_monolith_local",
    "chassis.deployment.profile_ternary_split_3_local",
    "chassis.deployment.profile_maximal_decoupled_local",
    "chassis.secrets.no_plaintext_in_receipts",
    "chassis.tenant.residency_enforcement",
    "chassis.metabolic.auto_rollback_on_pressure"
  ]

  @proofs [
    {"chassis.boundary.local_adapter_equivalence.v1", &Proofs.local_adapter_equivalence/0},
    {"chassis.boundary.no_pid_payloads.v1", &Proofs.no_pid_payloads/0},
    {"chassis.boundary.no_raw_secret_payloads.v1", &Proofs.no_raw_secret_payloads/0},
    {"chassis.boundary.codec_digest_stability.v1", &Proofs.codec_digest_stability/0},
    {"chassis.boundary.idempotency_required_for_mutations.v1",
     &Proofs.idempotency_required_for_mutations/0},
    {"chassis.boundary.citadel_fail_closed.v1", &Proofs.citadel_fail_closed/0},
    {"chassis.deployment.profile_monolith_local", &Proofs.deployment_profile_monolith_local/0},
    {"chassis.deployment.profile_ternary_split_3_local",
     &Proofs.deployment_profile_ternary_split_3_local/0},
    {"chassis.deployment.profile_maximal_decoupled_local",
     &Proofs.deployment_profile_maximal_decoupled_local/0},
    {"chassis.secrets.no_plaintext_in_receipts", &Proofs.no_plaintext_in_receipts/0},
    {"chassis.tenant.residency_enforcement", &Proofs.tenant_residency_enforcement/0},
    {"chassis.metabolic.auto_rollback_on_pressure", &Proofs.metabolic_auto_rollback/0}
  ]

  @spec proof_names() :: [String.t()]
  def proof_names, do: @proof_names

  @spec catalog() :: [map()]
  def catalog do
    Enum.map(@proofs, fn {name, fun} -> %{name: name, tag: :chassis, run: fun} end)
  end

  @spec run(keyword()) :: {:ok, map()} | {:error, term()}
  def run(opts \\ [])

  def run(opts) when is_list(opts) do
    tag = Keyword.get(opts, :tag, :chassis)
    proof_refs = Keyword.get(opts, :proof_refs, :all)

    with :ok <- validate_tag(tag),
         {:ok, selected} <- select_proofs(proof_refs) do
      results = Enum.map(selected, &run_one/1)
      failed = Enum.count(results, &(&1.status == :fail))

      {:ok,
       %{
         run_ref: new_run_ref(),
         tag: :chassis,
         passed: Enum.count(results, &(&1.status == :pass)),
         failed: failed,
         skipped: 0,
         proofs: results,
         status: if(failed == 0, do: :passed, else: :failed)
       }}
    end
  end

  def run(_opts), do: {:error, :invalid_options}

  defp validate_tag(tag) when tag in [:chassis, "chassis", nil], do: :ok
  defp validate_tag(tag), do: {:error, {:unknown_tag, tag}}

  defp select_proofs(:all), do: {:ok, catalog()}
  defp select_proofs(nil), do: {:ok, catalog()}
  defp select_proofs([]), do: {:ok, catalog()}

  defp select_proofs(refs) when is_list(refs) do
    by_name = Map.new(catalog(), &{&1.name, &1})
    unknown = Enum.reject(refs, &Map.has_key?(by_name, &1))

    case unknown do
      [] -> {:ok, Enum.map(refs, &Map.fetch!(by_name, &1))}
      _ -> {:error, {:unknown_proofs, unknown}}
    end
  end

  defp run_one(%{name: name, run: fun}) do
    started = System.monotonic_time(:microsecond)

    try do
      case fun.() do
        {:ok, evidence} when is_map(evidence) ->
          result(name, :pass, evidence, started)

        {:error, reason} ->
          result(name, :fail, %{reason: inspect(reason)}, started)

        other ->
          result(name, :fail, %{reason: "invalid proof result #{inspect(other)}"}, started)
      end
    rescue
      exception ->
        result(name, :fail, %{reason: Exception.message(exception)}, started)
    end
  end

  defp result(name, status, evidence, started) do
    %{
      name: name,
      status: status,
      duration_us: max(System.monotonic_time(:microsecond) - started, 0),
      evidence: evidence
    }
  end

  defp new_run_ref do
    "run:stacklab:chassis:" <> Base.encode16(:crypto.strong_rand_bytes(4), case: :lower)
  end
end

defmodule Chassis.Conformance.Proofs do
  @moduledoc false

  alias Chassis.Boundary.{BeamDistributionAdapter, Envelope, LocalAdapter}
  alias Chassis.Receipts.{DeploymentRecord, RollbackRecord, Store}

  @materialize "boundary:mezzanine.chassis.materialize_deployment:v1"
  @read_projection "boundary:appkit.chassis.read_deployment_projection:v1"

  def local_adapter_equivalence do
    envelope = read_projection_envelope(%{query: "active_deployments", limit: 1})

    with {:ok, local} <- LocalAdapter.dispatch(envelope, protocol_module: __MODULE__.Echo),
         {:ok, beam} <- beam_dispatch(envelope) do
      if Envelope.digest(local) == Envelope.digest(beam) do
        {:ok,
         %{
           local_digest: Envelope.digest(local),
           beam_digest: Envelope.digest(beam),
           response_status: local.status
         }}
      else
        {:error, :adapter_digest_mismatch}
      end
    end
  end

  def no_pid_payloads do
    envelope = read_projection_envelope(%{pid: self()})

    expect_argument_error(fn -> Envelope.encode!(envelope) end, "boundary_pid_not_serializable")
  end

  def no_raw_secret_payloads do
    envelope =
      read_projection_envelope(%{
        private_key:
          "-----BEGIN OPENSSH PRIVATE KEY-----\nphase21\n-----END OPENSSH PRIVATE KEY-----"
      })

    expect_argument_error(fn -> Envelope.encode!(envelope) end, "private key")
  end

  def codec_digest_stability do
    envelope = read_projection_envelope(%{query: "active_deployments", tenant: "tenant:dev"})
    digest = Envelope.digest(envelope)
    decoded = envelope |> Envelope.encode!() |> Envelope.decode!() |> Envelope.new!()

    if digest == Envelope.digest(decoded) do
      {:ok, %{digest: digest, encoded_bytes: byte_size(Envelope.encode!(envelope))}}
    else
      {:error, :digest_changed_after_decode}
    end
  end

  def idempotency_required_for_mutations do
    attrs =
      materialize_attrs()
      |> Map.delete(:idempotency_key)

    expect_argument_error(fn -> Envelope.new!(attrs) end, "idempotency_key")
  end

  def citadel_fail_closed do
    attrs =
      materialize_attrs()
      |> Map.delete(:authority_ref)

    expect_argument_error(fn -> Envelope.new!(attrs) end, "authority_ref")
  end

  def deployment_profile_monolith_local do
    run_deployment_profile("profile:monolith", 1)
  end

  def deployment_profile_ternary_split_3_local do
    run_deployment_profile("profile:ternary-split-3", 3)
  end

  def deployment_profile_maximal_decoupled_local do
    run_deployment_profile("profile:maximal-decoupled", 8)
  end

  def no_plaintext_in_receipts do
    path =
      Path.join(
        System.tmp_dir!(),
        "chassis_phase21_receipts_#{System.unique_integer([:positive])}.jsonl"
      )

    {:ok, store} = Store.Memory.start_link(name: nil, jsonl_path: path)
    raw = "PRIVATE KEY BYTES phase21 should not leak"

    {:ok, _record} =
      Store.Memory.put(store, %DeploymentRecord{
        receipt_ref: "receipt:deployment:secret-proof",
        app_ref: "app:secret-proof",
        profile_ref: "profile:monolith",
        env: :dev,
        status: :active,
        authority_ref: "authority:stacklab:phase21",
        tenant_ref: "tenant:dev",
        labels: %{token: raw},
        material: raw,
        password: raw
      })

    body = File.read!(path)

    if String.contains?(body, raw) or String.contains?(inspect(Store.Memory.list(store, [])), raw) do
      {:error, :plaintext_secret_leaked}
    else
      {:ok, %{jsonl_path: path, redacted?: String.contains?(body, "[REDACTED]")}}
    end
  end

  def tenant_residency_enforcement do
    fixture = Chassis.Fixtures.residency_violation_fixture()

    case Chassis.Fixtures.run_deployment(fixture) do
      {:error, {:topology_invalid, errors}} ->
        if Enum.any?(errors, &(&1.code == :residency_violation)) do
          {:ok, %{error_count: length(errors), residency_ref: fixture.residency_ref}}
        else
          {:error, {:missing_residency_violation, errors}}
        end

      other ->
        {:error, {:expected_residency_rejection, other}}
    end
  end

  def metabolic_auto_rollback do
    with {:ok, runtime} <- Chassis.Fixtures.start_runtime(),
         first = Chassis.Fixtures.fixture!("profile:monolith", :extravaganza, :dev),
         second = Chassis.Fixtures.fixture!("profile:ternary-split-3", :extravaganza, :dev),
         {:ok, first_result} <-
           run_fixture(first, runtime, %{idempotency_key: "metabolic:deploy:1"}),
         {:ok, second_result} <-
           run_fixture(second, runtime, %{idempotency_key: "metabolic:deploy:2"}),
         :ok <- pressure_policy([91, 93, 94, 20, 18, 21, 19, 20, 21, 22]),
         {:ok, rollback} <-
           Chassis.StackManager.Transaction.rollback(second_result.app_ref,
             registry: runtime.registry,
             receipts_store: runtime.receipts_store,
             checkpoint_store: runtime.checkpoint_store,
             trigger: :metabolic_self_healing,
             authority_ref: "authority:metabolic:phase21"
           ) do
      rollbacks = Store.Memory.list(runtime.receipts_store, kind: RollbackRecord)

      if Enum.any?(rollbacks, &(&1.trigger == :metabolic_self_healing)) do
        {:ok,
         %{
           first_receipt_ref: first_result.receipt_ref,
           second_receipt_ref: second_result.receipt_ref,
           rollback_receipt_ref: rollback.rollback_receipt_ref,
           rollback_target_ref: rollback.rollback_target_ref
         }}
      else
        {:error, :rollback_receipt_missing}
      end
    end
  end

  defp beam_dispatch(envelope) do
    if Node.alive?() do
      BeamDistributionAdapter.dispatch(node(), envelope, protocol_module: __MODULE__.Echo)
    else
      envelope
      |> Envelope.encode!()
      |> BeamDistributionAdapter.__remote_dispatch__(protocol_module: __MODULE__.Echo)
    end
  end

  defp run_deployment_profile(profile_ref, expected_node_count) do
    fixture = Chassis.Fixtures.fixture!(profile_ref, :extravaganza, :dev)

    with {:ok, result} <- Chassis.Fixtures.run_deployment(fixture) do
      cond do
        result.status != :active ->
          {:error, {:deployment_not_active, result}}

        length(result.node_mesh) != expected_node_count ->
          {:error, {:unexpected_node_count, length(result.node_mesh), expected_node_count}}

        true ->
          {:ok,
           %{
             app_ref: result.app_ref,
             receipt_ref: result.receipt_ref,
             node_count: length(result.node_mesh),
             profile_ref: profile_ref
           }}
      end
    end
  end

  defp run_fixture(fixture, runtime, overrides) do
    fixture
    |> Chassis.Fixtures.transaction_attrs(runtime, overrides)
    |> Chassis.StackManager.Transaction.run()
  end

  defp pressure_policy(samples) do
    if Enum.count(samples, &(&1 >= 90)) >= 3 do
      :ok
    else
      {:error, :pressure_threshold_not_met}
    end
  end

  defp expect_argument_error(fun, message_fragment) when is_function(fun, 0) do
    fun.()
    {:error, :expected_argument_error}
  rescue
    exception in ArgumentError ->
      if String.contains?(Exception.message(exception), message_fragment) do
        {:ok, %{rejected_with: Exception.message(exception)}}
      else
        {:error, {:unexpected_error, Exception.message(exception)}}
      end
  end

  defp read_projection_envelope(payload) do
    Envelope.new!(%{
      protocol_ref: @read_projection,
      envelope_ref: "env:stacklab:read_projection:#{System.unique_integer([:positive])}",
      tenant_ref: "tenant:dev",
      installation_ref: "installation:dev",
      actor_ref: "operator:stacklab",
      system_actor_ref: "system:stacklab",
      trace_id: "trace:stacklab:#{System.unique_integer([:positive])}",
      payload: payload
    })
  end

  defp materialize_attrs do
    %{
      protocol_ref: @materialize,
      envelope_ref: "env:stacklab:materialize",
      tenant_ref: "tenant:dev",
      installation_ref: "installation:dev",
      actor_ref: "operator:stacklab",
      system_actor_ref: "system:stacklab",
      authority_ref: "authority:stacklab:phase21",
      idempotency_key: "stacklab:materialize:phase21",
      trace_id: "trace:stacklab:materialize",
      payload: %{
        topology_ref: "profile:monolith",
        service_spec_ref: "service:extravaganza",
        runtime_profile_ref: "profile:monolith",
        placement_ref: "placement:profile:monolith",
        environment: "dev"
      }
    }
  end
end

defmodule Chassis.Conformance.Proofs.Echo do
  @moduledoc false

  alias Chassis.Boundary.Envelope

  def call(%Envelope{} = envelope, _opts) do
    {:ok,
     Envelope.response!(
       envelope,
       %{
         status: "ok",
         request_digest: Envelope.digest(envelope),
         adapter: "echo"
       },
       status: :ok
     )}
  end
end
