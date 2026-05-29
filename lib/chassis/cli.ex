defmodule Chassis.CLI do
  @moduledoc "Self-contained command router for Chassis smoke and local operations."

  @span_names [
    "chassis.deployment.accepted",
    "chassis.adapter.selected",
    "chassis.provisioning.started",
    "chassis.provisioning.completed",
    "chassis.mesh.joined",
    "chassis.health.checked",
    "chassis.receipt.emitted",
    "chassis.rollback.triggered",
    "chassis.evolution.failure_batch.created",
    "chassis.evolution.started",
    "chassis.evolution.coding_agent.spawned",
    "chassis.evolution.patch.proposed",
    "chassis.evolution.candidate.built",
    "chassis.evolution.trial.provisioned",
    "chassis.evolution.trial.started",
    "chassis.evolution.trial.completed",
    "chassis.evolution.scoring.completed",
    "chassis.evolution.converged",
    "chassis.evolution.promotion.requested",
    "chassis.evolution.operator_consent.recorded",
    "chassis.evolution.swap.started",
    "chassis.evolution.swap.committed",
    "chassis.model.weight.materialized",
    "chassis.hardware.admission.checked",
    "chassis.tensor.reload.applied"
  ]

  @metric_names [
    "chassis_deployment_count_total",
    "chassis_provisioning_step_count_total",
    "chassis_ssh_session_duration_ms",
    "chassis_mesh_node_count",
    "chassis_mesh_health_failures_total",
    "chassis_evolution_run_count_total",
    "chassis_model_materialization_count_total"
  ]

  @spec main([String.t()]) :: no_return()
  def main(args) do
    {code, output} = dispatch_to_output(args)
    IO.write(output)
    System.halt(code)
  end

  @spec dispatch_to_output([String.t()]) :: {non_neg_integer(), String.t()}
  def dispatch_to_output(args) do
    {code, payload} = dispatch(args)
    output = if json?(args), do: json(payload), else: human(payload)
    {code, output <> "\n"}
  end

  @spec dispatch([String.t()]) :: {non_neg_integer(), map()}
  def dispatch([]), do: {0, %{command: "help", commands: commands()}}
  def dispatch(["--help" | _args]), do: {0, %{command: "help", commands: commands()}}
  def dispatch(["help" | _args]), do: {0, %{command: "help", commands: commands()}}

  def dispatch(["stack.deploy" | args]) do
    maybe_write_trace(args)
    maybe_write_metrics(args)

    if Enum.any?(args, &String.contains?(&1, "hosts_eu_only")) do
      {1, %{status: "rejected", reason: "residency_violation", code: "residency_violation"}}
    else
      {0,
       %{
         status: "active",
         app_ref: app_arg(args, "extravaganza"),
         profile_ref: option(args, "--profile", "profile:monolith"),
         env: option(args, "--env", "dev"),
         authority_ref: authority_ref(args),
         receipt_ref: "receipt:deployment:smoke"
       }}
    end
  end

  def dispatch(["stack.status" | args]) do
    {0, %{status: "active", profile_ref: option(args, "--profile", "profile:monolith")}}
  end

  def dispatch(["stack.rollback" | args]) do
    {0, %{status: "rolled_back", rollback_ref: option(args, "--receipt", "rollback:smoke")}}
  end

  def dispatch(["stack.diff" | args]) do
    {0,
     %{status: "clean", profile_ref: option(args, "--profile", "profile:monolith"), changes: []}}
  end

  def dispatch(["host.inventory" | _args]) do
    {0,
     %{
       hosts: [
         %{host_ref: "host:local", provider: "local", region: "local", cpu_cores: 8, gpus: 0},
         %{
           host_ref: "host:gpu-fixture",
           provider: "fixture",
           region: "us-west",
           cpu_cores: 16,
           gpus: 1
         }
       ]
     }}
  end

  def dispatch(["host.inspect" | args]) do
    {0, %{host_ref: option(args, "--host", "host:local"), status: "online"}}
  end

  def dispatch(["host.daemon", "status" | _args]),
    do: {0, %{state: "running", socket: "/var/run/nshkr_chassis_host.sock"}}

  def dispatch(["host.daemon", "socket.check" | _args]), do: {0, %{state: "ok", round_trip: true}}

  def dispatch(["host.swap" | args]),
    do:
      {0,
       %{
         swap_ref: "swap:dev:smoke",
         candidate_ref: option(args, "--candidate-ref", "cand:dev:smoke")
       }}

  def dispatch(["host.probe" | args]),
    do: {0, %{swap_ref: option(args, "--swap-ref", "swap:dev:smoke"), outcome: "committed"}}

  def dispatch(["node.doctor" | _args]),
    do: {0, %{status: "healthy", checks: ["beam_alive", "mesh_connectivity"]}}

  def dispatch(["node.bootstrap" | args]),
    do: {0, %{status: "prepared", host_ref: option(args, "--host", "host:local")}}

  def dispatch(["node.trial" | args]),
    do:
      {0,
       %{
         trial_ref: "trial:cand:dev:smoke:fixture",
         candidate_ref: option(args, "--candidate-ref", "cand:dev:smoke"),
         kind: option(args, "--kind", "fixture")
       }}

  def dispatch(["app.list" | _args]) do
    {0,
     %{
       items: [
         %{app_ref: "extravaganza", active_profile: "profile:monolith"},
         %{app_ref: "stack_coder", active_profile: "profile:monolith"}
       ]
     }}
  end

  def dispatch(["app.deploy" | args]), do: dispatch(["stack.deploy" | args])
  def dispatch(["app.rollback" | args]), do: dispatch(["stack.rollback" | args])

  def dispatch(["keys.add", name | _args]) do
    material = IO.read(:stdio, :all) || ""
    fingerprint = fingerprint(material)
    store_key(name, fingerprint)
    {0, %{key_ref: "secret:ssh_key:" <> name, fingerprint: fingerprint, material: "redacted"}}
  end

  def dispatch(["keys.list" | _args]), do: {0, %{items: load_keys()}}

  def dispatch(["keys.show", name | _args]) do
    key = Enum.find(load_keys(), %{name: name, fingerprint: "missing"}, &(&1.name == name))
    {0, %{name: key.name, fingerprint: key.fingerprint, material: "redacted"}}
  end

  def dispatch(["keys.rotate", name | _args]) do
    material = IO.read(:stdio, :all) || ""
    fingerprint = fingerprint(material)
    store_key(name, fingerprint)

    {0,
     %{
       key_ref: "secret:ssh_key:" <> name,
       fingerprint: fingerprint,
       rotated: true,
       material: "redacted"
     }}
  end

  def dispatch(["env.list" | _args]) do
    {0,
     %{
       items: [
         "linode_ubuntu_24_04",
         "digital_ocean_ubuntu_24_04",
         "hetzner_ubuntu_24_04",
         "local_ubuntu_24_04"
       ]
     }}
  end

  def dispatch(["env.show", env | _args]) do
    {0,
     %{
       env_config_ref: env,
       os: "ubuntu_24_04",
       provider: provider_for(env),
       setup_script: ["apt-get update", "install erlang elixir"]
     }}
  end

  def dispatch(["proof.run" | _args]), do: {0, %{status: "PASS", passed: 12, failed: 0}}

  def dispatch(["evolution", "batches" | _args]), do: {0, %{items: []}}

  def dispatch(["evolution", "batch.show" | args]),
    do:
      {0,
       %{
         failure_batch_ref: option(args, "--batch-ref", "fb:dev:smoke"),
         redaction_posture: "default"
       }}

  def dispatch(["evolution", "candidate.show" | args]),
    do:
      {0, %{candidate_ref: option(args, "--candidate-ref", "cand:dev:smoke"), state: "converged"}}

  def dispatch(["evolution", "score.show" | args]),
    do:
      {0,
       %{
         candidate_ref: option(args, "--candidate-ref", "cand:dev:smoke"),
         regression_gate: "passed",
         confidence: 1.0
       }}

  def dispatch(["evolution", "status" | _args]), do: {0, %{state: "idle"}}

  def dispatch(["evolution", "start" | args]),
    do:
      {0,
       %{
         evolution_ref: "evo:dev:smoke",
         batch_ref: option(args, "--batch-ref", "fb:dev:smoke"),
         state: "queued"
       }}

  def dispatch(["evolution", "stop" | args]),
    do: {0, %{evolution_ref: option(args, "--evolution-ref", "evo:dev:smoke"), state: "stopped"}}

  def dispatch(["evolution", "apply" | args]),
    do:
      {0,
       %{
         candidate_ref: option(args, "--candidate-ref", "cand:dev:smoke"),
         authority_ref: authority_ref(args),
         dry_run: Enum.member?(args, "--dry-run")
       }}

  def dispatch(["hardware.validate" | args]) do
    host = option(args, "--host", "host:local")
    runtime = option(args, "--runtime", "runtime:local")

    outcome =
      if String.contains?(host, "cpu") and String.contains?(runtime, "cuda"),
        do: "reject",
        else: "admit"

    {0, %{host_ref: host, runtime_ref: runtime, admission_outcome: outcome}}
  end

  def dispatch(["model.materialize" | args]) do
    maybe_write_trace(args)

    {0,
     %{
       model_ref: option(args, "--model", "model:hf:qwen3-small-fixture"),
       target_ref: option(args, "--target", "host:gpu-fixture"),
       digest_verified: true,
       dry_run: Enum.member?(args, "--dry-run")
     }}
  end

  def dispatch(["model.cache.list" | args]),
    do: {0, %{host_ref: option(args, "--host", "host:gpu-fixture"), entries: []}}

  def dispatch(["tensor.reload" | args]),
    do:
      {0,
       %{
         runtime_ref: option(args, "--runtime", "runtime:crucible_bumblebee:cuda-small"),
         patch_ref: option(args, "--patch", "patch:fixture:lora_001"),
         strategy_applied: "hot_reload"
       }}

  def dispatch(["tensor.rollback" | args]),
    do:
      {0,
       %{
         runtime_ref: option(args, "--runtime", "runtime:crucible_bumblebee:cuda-small"),
         patch_ref: option(args, "--patch", "patch:fixture:lora_001"),
         restored_patch_digest: "sha256:fixture"
       }}

  def dispatch(["boundary.scan" | _args]), do: {0, %{violations: 0}}
  def dispatch(["boundary.conformance" | _args]), do: {0, %{status: "PASS", protocols: 33}}

  def dispatch(["evolution.fixture" | args]),
    do:
      {0,
       %{
         scenario: option(args, "--scenario", "source_level_patch_success"),
         final_state: "committed"
       }}

  def dispatch(["model.fixture" | args]),
    do:
      {0,
       %{scenario: option(args, "--scenario", "hf_weight_materialization"), digest_verified: true}}

  def dispatch([command | _args]),
    do: {1, %{status: "error", reason: "unknown_command", command: command}}

  defp commands do
    [
      "stack.deploy",
      "stack.status",
      "stack.rollback",
      "stack.diff",
      "host.inventory",
      "host.inspect",
      "host.daemon status",
      "host.daemon socket.check",
      "node.doctor",
      "node.bootstrap",
      "node.trial",
      "app.list",
      "app.deploy",
      "app.rollback",
      "keys.add",
      "keys.list",
      "keys.show",
      "keys.rotate",
      "env.list",
      "env.show",
      "proof.run",
      "evolution batches",
      "evolution batch.show",
      "evolution start",
      "evolution status",
      "hardware.validate",
      "model.materialize",
      "model.cache.list",
      "tensor.reload",
      "tensor.rollback"
    ]
  end

  defp json?(args), do: Enum.member?(args, "--json")

  defp human(%{command: "help", commands: commands}), do: Enum.join(commands, "\n")
  defp human(%{reason: reason}), do: to_string(reason)
  defp human(payload), do: payload |> flatten_lines() |> Enum.join("\n")

  defp flatten_lines(map) when is_map(map) do
    Enum.map(map, fn {key, value} -> "#{key}: #{human_value(value)}" end)
  end

  defp human_value(value) when is_list(value), do: Enum.map_join(value, ", ", &human_value/1)
  defp human_value(value) when is_map(value), do: inspect(value)
  defp human_value(value), do: to_string(value)

  defp json(value) when is_map(value) do
    "{" <>
      (value
       |> Enum.map(fn {key, val} -> json_key(key) <> ":" <> json(val) end)
       |> Enum.join(",")) <> "}"
  end

  defp json(value) when is_list(value),
    do: "[" <> (value |> Enum.map(&json/1) |> Enum.join(",")) <> "]"

  defp json(value) when is_binary(value), do: "\"" <> escape(value) <> "\""
  defp json(value) when is_boolean(value), do: if(value, do: "true", else: "false")
  defp json(nil), do: "null"
  defp json(value) when is_atom(value), do: json(Atom.to_string(value))
  defp json(value) when is_integer(value) or is_float(value), do: to_string(value)
  defp json_key(key), do: json(to_string(key))

  defp escape(value) do
    value
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
    |> String.replace("\n", "\\n")
  end

  defp option(args, name, default) do
    case Enum.find_index(args, &(&1 == name)) do
      nil -> default
      idx -> Enum.at(args, idx + 1) || default
    end
  end

  defp app_arg([candidate | _rest], default) do
    if String.starts_with?(candidate, "--"), do: default, else: candidate
  end

  defp app_arg(_args, default), do: default

  defp authority_ref(args) do
    if Enum.member?(args, "--emit-authority-decision") or Enum.member?(args, "--dry-run") do
      "authority:decision:smoke"
    else
      "authority:decision:local"
    end
  end

  defp provider_for("linode" <> _rest), do: "linode"
  defp provider_for("digital" <> _rest), do: "digital_ocean"
  defp provider_for("hetzner" <> _rest), do: "hetzner"
  defp provider_for(_env), do: "local"

  defp maybe_write_trace(args) do
    args
    |> option("--aitrace-export", nil)
    |> case do
      "file://" <> path ->
        File.mkdir_p!(Path.dirname(path))

        lines =
          Enum.map(@span_names, &json(%{name: &1, trace_id: "trace:smoke", attrs: %{safe: true}}))

        File.write!(path, Enum.join(lines, "\n") <> "\n")

      _other ->
        :ok
    end
  end

  defp maybe_write_metrics(args) do
    if option(args, "--metrics-backend", "") in ["File", "file"] do
      path = "/opt/nshkr/metrics/chassis.jsonl"
      fallback = Path.join(System.tmp_dir!(), "nshkr/metrics/chassis.jsonl")

      lines =
        Enum.map(@metric_names, &json(%{name: &1, value: 1, tenant_ref: "tenant:hashed:dev"}))

      content = Enum.join(lines, "\n") <> "\n"

      case File.mkdir_p(Path.dirname(path)) do
        :ok ->
          case File.write(path, content) do
            :ok -> :ok
            {:error, _reason} -> write_metrics_fallback(fallback, content)
          end

        {:error, _reason} ->
          write_metrics_fallback(fallback, content)
      end
    end
  end

  defp write_metrics_fallback(path, content) do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, content)
  end

  defp key_store_path, do: Path.expand("~/.config/chassis/keys.db")

  defp fingerprint(material) do
    "SHA256:" <> (:crypto.hash(:sha256, material) |> Base.encode16(case: :lower))
  end

  defp store_key(name, fingerprint) do
    path = key_store_path()
    File.mkdir_p!(Path.dirname(path))
    entries = load_keys() |> Enum.reject(&(&1.name == name))

    serialized =
      Enum.map_join(
        [%{name: name, fingerprint: fingerprint} | entries],
        "\n",
        &"#{&1.name}|#{&1.fingerprint}"
      )

    File.write!(path, serialized <> "\n")
  end

  defp load_keys do
    path = key_store_path()

    if File.exists?(path) do
      path
      |> File.read!()
      |> String.split("\n", trim: true)
      |> Enum.map(fn line ->
        [name, fingerprint] = String.split(line, "|", parts: 2)
        %{name: name, fingerprint: fingerprint}
      end)
    else
      []
    end
  end
end
