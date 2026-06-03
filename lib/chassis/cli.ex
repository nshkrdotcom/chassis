defmodule Chassis.CLI do
  @moduledoc """
  Workspace-root escript entry point. This module is what the
  `escript: [main_module: Chassis.CLI, name: "chassis"]` setting in the root
  `mix.exs` boots into when a user runs `./chassis <subcommand>`.

  Per `0541_implementation_readiness_corrections.md` §4, the canonical CLI
  router lives in `manager/chassis_cli/lib/chassis/cli.ex`. The workspace-root
  copy is a strict not-implemented dispatcher that uses the **same command
  table** so the static_cli_path classification cannot leak in through the
  escript bundle. Output shaping is performed by `Chassis.CLI.Encoding`.

  Behavior is identical to the manager-package CLI:

  * Unknown command -> `{1, %{error: "unknown_command", ...}}`.
  * Known command whose `Chassis.CLI.Command.*` module is not loaded ->
    `{1, %{error: "not_implemented", phase_gate: N, package: :chassis_*, ...}}`.
  * Known command whose `Chassis.CLI.Command.*` module IS loaded -> dispatch
    to its `run/2` callback and stamp `command:` on the returned payload.

  This file MUST NOT embed any per-subcommand success payload. Phase 0 step C.2
  removed the prior 499-line static router that returned baked
  `receipt:deployment:smoke`, `status: "active"`, `passed: 12, failed: 0`,
  `outbox:chassis:smoke`, and similar fictive payloads.
  """

  @command_table %{
    "stack.deploy" =>
      {Chassis.CLI.Command.Stack.Deploy, phase: 11, package: :chassis_stack_manager},
    "stack.status" =>
      {Chassis.CLI.Command.Stack.Status, phase: 11, package: :chassis_stack_manager},
    "stack.rollback" =>
      {Chassis.CLI.Command.Stack.Rollback, phase: 11, package: :chassis_stack_manager},
    "stack.diff" => {Chassis.CLI.Command.Stack.Diff, phase: 11, package: :chassis_stack_manager},
    "app.list" => {Chassis.CLI.Command.App.List, phase: 5, package: :chassis_releases},
    "app.deploy" => {Chassis.CLI.Command.App.Deploy, phase: 11, package: :chassis_stack_manager},
    "app.rollback" =>
      {Chassis.CLI.Command.App.Rollback, phase: 11, package: :chassis_stack_manager},
    "host.inventory" =>
      {Chassis.CLI.Command.Host.Inventory, phase: 3, package: :chassis_inventory},
    "host.inspect" => {Chassis.CLI.Command.Host.Inspect, phase: 3, package: :chassis_inventory},
    "host.swap" => {Chassis.CLI.Command.Host.Swap, phase: 30, package: :chassis_swap_supervisor},
    "host.probe" => {Chassis.CLI.Command.Host.Probe, phase: 30, package: :chassis_health_probe},
    "host.daemon.status" =>
      {Chassis.CLI.Command.Host.Daemon.Status, phase: 29, package: :chassis_host_daemon},
    "host.daemon.socket.check" =>
      {Chassis.CLI.Command.Host.Daemon.SocketCheck, phase: 29, package: :chassis_host_daemon},
    "node.doctor" => {Chassis.CLI.Command.Node.Doctor, phase: 3, package: :chassis_doctor},
    "node.bootstrap" =>
      {Chassis.CLI.Command.Node.Bootstrap, phase: 7, package: :chassis_bootstrap},
    "node.trial" =>
      {Chassis.CLI.Command.Node.Trial, phase: 28, package: :chassis_trial_supervisor},
    "keys.add" => {Chassis.CLI.Command.Keys.Add, phase: 10, package: :chassis_secret_sops},
    "keys.list" => {Chassis.CLI.Command.Keys.List, phase: 10, package: :chassis_secret_sops},
    "keys.show" => {Chassis.CLI.Command.Keys.Show, phase: 10, package: :chassis_secret_sops},
    "keys.rotate" => {Chassis.CLI.Command.Keys.Rotate, phase: 10, package: :chassis_secret_sops},
    "env.list" => {Chassis.CLI.Command.Env.List, phase: 6, package: :chassis_environments},
    "env.show" => {Chassis.CLI.Command.Env.Show, phase: 6, package: :chassis_environments},
    "proof.run" => {Chassis.CLI.Command.Proof.Run, phase: 21, package: :chassis_stacklab_bridge},
    "evolution.batches" =>
      {Chassis.CLI.Command.Evolution.Batches, phase: 23, package: :chassis_failure_batches},
    "evolution.batch.show" =>
      {Chassis.CLI.Command.Evolution.BatchShow, phase: 23, package: :chassis_failure_batches},
    "evolution.candidate.show" =>
      {Chassis.CLI.Command.Evolution.CandidateShow,
       phase: 26, package: :chassis_candidate_registry},
    "evolution.score.show" =>
      {Chassis.CLI.Command.Evolution.ScoreShow, phase: 32, package: :chassis_candidate_scoring},
    "evolution.status" =>
      {Chassis.CLI.Command.Evolution.Status, phase: 24, package: :chassis_evolution_core},
    "evolution.start" =>
      {Chassis.CLI.Command.Evolution.Start, phase: 24, package: :chassis_evolution_core},
    "evolution.stop" =>
      {Chassis.CLI.Command.Evolution.Stop, phase: 24, package: :chassis_evolution_core},
    "evolution.apply" =>
      {Chassis.CLI.Command.Evolution.Apply, phase: 34, package: :chassis_evolution_core},
    "evolution.fixture" =>
      {Chassis.CLI.Command.Evolution.Fixture, phase: 36, package: :chassis_evolution_conformance},
    "evolution.proof" =>
      {Chassis.CLI.Command.Evolution.Proof, phase: 36, package: :chassis_evolution_conformance},
    "hardware.validate" =>
      {Chassis.CLI.Command.Hardware.Validate, phase: 37, package: :chassis_hardware_guard},
    "model.materialize" =>
      {Chassis.CLI.Command.Model.Materialize, phase: 40, package: :chassis_weight_materializer},
    "model.cache.list" =>
      {Chassis.CLI.Command.Model.CacheList, phase: 40, package: :chassis_model_cache},
    "model.fixture" =>
      {Chassis.CLI.Command.Model.Fixture, phase: 41, package: :chassis_model_asset_conformance},
    "tensor.reload" =>
      {Chassis.CLI.Command.Tensor.Reload, phase: 42, package: :chassis_tensor_reload},
    "tensor.rollback" =>
      {Chassis.CLI.Command.Tensor.Rollback, phase: 42, package: :chassis_tensor_reload},
    "boundary.scan" => {Chassis.CLI.Command.Boundary.Scan, phase: 9, package: :chassis_boundary},
    "boundary.conformance" =>
      {Chassis.CLI.Command.Boundary.Conformance, phase: 21, package: :chassis_conformance}
  }

  @spec command_table() :: map()
  def command_table, do: @command_table

  @spec known_commands() :: [String.t()]
  def known_commands, do: @command_table |> Map.keys() |> Enum.sort()

  @spec main([String.t()]) :: no_return()
  def main(argv) do
    {code, payload} = dispatch(argv)
    IO.write(encode(payload, json?: json?(argv)) <> "\n")
    System.halt(code)
  end

  @spec dispatch_to_output([String.t()]) :: {non_neg_integer(), String.t()}
  def dispatch_to_output(argv) do
    {code, payload} = dispatch(argv)
    {code, encode(payload, json?: json?(argv)) <> "\n"}
  end

  @spec dispatch([String.t()]) :: {non_neg_integer(), map()}
  def dispatch([]), do: {0, %{command: "help", commands: known_commands()}}
  def dispatch(["help" | _]), do: {0, %{command: "help", commands: known_commands()}}
  def dispatch(["--help" | _]), do: {0, %{command: "help", commands: known_commands()}}

  def dispatch(argv) do
    {key, rest} = resolve_key(argv)
    {positional, switches} = parse_switches(rest)

    case Map.fetch(@command_table, key) do
      :error ->
        {1, %{error: "unknown_command", command: key, known_commands: known_commands()}}

      {:ok, {module, meta}} ->
        invoke(module, positional, switches, key, meta)
    end
  end

  defp resolve_key([a, b | rest]) do
    joined = a <> "." <> b

    cond do
      Map.has_key?(@command_table, joined) -> {joined, rest}
      Map.has_key?(@command_table, a) -> {a, [b | rest]}
      true -> {a, [b | rest]}
    end
  end

  defp resolve_key([a | rest]), do: {a, rest}
  defp resolve_key([]), do: {"help", []}

  defp parse_switches(argv) do
    {parsed, positional, _invalid} =
      OptionParser.parse(argv,
        strict: [
          app: :string,
          dry_run: :boolean,
          env: :string,
          fixture: :string,
          from: :string,
          git_sha: :string,
          host: :string,
          hosts: :string,
          idempotency_key: :string,
          installation: :string,
          isolation: :string,
          json: :boolean,
          material_file: :string,
          model: :string,
          no_mezzanine: :boolean,
          patch: :string,
          plaintext_vault: :boolean,
          profile: :string,
          quota: :string,
          receipts_dir: :string,
          release_version: :string,
          require_citadel_consent: :boolean,
          require_health_gated_swap: :boolean,
          require_rollback_proof: :boolean,
          require_trial: :boolean,
          residency: :string,
          runtime: :string,
          scenario: :string,
          suite: :string,
          target: :string,
          tenant: :string,
          to: :string,
          vault_path: :string,
          verify_sha256: :boolean
        ],
        aliases: [p: :profile]
      )

    {positional, Map.new(parsed)}
  rescue
    _ -> {argv, %{}}
  end

  defp invoke(module, positional, switches, key, meta) do
    if Code.ensure_loaded?(module) and function_exported?(module, :run, 2) do
      case module.run(positional, switches) do
        {:ok, payload} when is_map(payload) ->
          {0, Map.put(payload, :command, key)}

        {:error, {:not_implemented, ^module, info}} when is_list(info) ->
          not_implemented(key, module, Keyword.merge(meta, info))

        {:error, {:not_implemented, ^module}} ->
          not_implemented(key, module, meta)

        {:error, %{} = err} ->
          {1, Map.merge(%{error: "command_failed", command: key}, err)}

        {:error, reason} ->
          {1, %{error: "command_failed", command: key, reason: inspect(reason)}}

        other ->
          {1,
           %{
             error: "command_returned_invalid_shape",
             command: key,
             module: inspect(module),
             value: inspect(other)
           }}
      end
    else
      not_implemented(key, module, meta)
    end
  end

  defp not_implemented(key, module, meta) do
    {1,
     %{
       error: "not_implemented",
       command: key,
       module: inspect(module),
       phase_gate: Keyword.get(meta, :phase),
       package: Keyword.get(meta, :package)
     }}
  end

  defp json?(argv), do: Enum.member?(argv, "--json")

  defp encode(payload, opts) when is_map(payload) do
    if Keyword.get(opts, :json?, false), do: json(payload), else: human(payload)
  end

  defp human(%{command: "help", commands: commands}),
    do: "commands:\n" <> Enum.map_join(commands, "\n", &("  " <> &1))

  defp human(%{error: error} = payload),
    do: "ERROR " <> to_string(error) <> ": " <> inspect(Map.delete(payload, :error))

  defp human(payload),
    do: payload |> Enum.map_join("\n", fn {k, v} -> "#{k}: #{format(v)}" end)

  defp format(v) when is_list(v), do: Enum.map_join(v, ", ", &format/1)
  defp format(v) when is_map(v), do: inspect(v)
  defp format(v), do: to_string(v)

  defp json(value) when is_map(value),
    do:
      "{" <>
        (value
         |> Enum.map(fn {k, v} -> json_key(k) <> ":" <> json(v) end)
         |> Enum.join(",")) <> "}"

  defp json(value) when is_list(value), do: "[" <> Enum.map_join(value, ",", &json/1) <> "]"
  defp json(value) when is_binary(value), do: "\"" <> escape(value) <> "\""
  defp json(value) when is_boolean(value), do: if(value, do: "true", else: "false")
  defp json(nil), do: "null"
  defp json(value) when is_atom(value), do: json(Atom.to_string(value))
  defp json(value) when is_integer(value) or is_float(value), do: to_string(value)
  defp json(value) when is_tuple(value), do: json(Tuple.to_list(value))
  defp json(value), do: json(inspect(value))

  defp json_key(k), do: json(to_string(k))

  defp escape(value) do
    value
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
    |> String.replace("\n", "\\n")
  end
end
