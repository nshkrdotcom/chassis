defmodule Chassis.CLI do
  @moduledoc """
  Argv-to-command-module router for the `chassis` escript.

  The CLI does not implement any subcommand behavior. Every documented command
  is resolved to a `Chassis.CLI.Command.*` module under the convention:

      "stack.deploy"          -> Chassis.CLI.Command.Stack.Deploy
      "evolution.start"       -> Chassis.CLI.Command.Evolution.Start
      "host.daemon socket.check" -> Chassis.CLI.Command.Host.Daemon.SocketCheck

  When a command module is **not loaded** (its underlying package has not been
  activated in the current phase, per
  `0537_chassis_full_ecosystem_package_map.md` §3), the CLI returns:

      {:error, %{error: "not_implemented", phase_gate: <phase>, package: <atom>}}

  with a non-zero exit code. This satisfies
  [`0499_execution_integrity_contract.md`](0499_execution_integrity_contract.md)
  §3 bullet 2 (no CLI response path that bypasses command modules) and
  [`0541_implementation_readiness_corrections.md`](0541_implementation_readiness_corrections.md)
  §3.3 (strict not-implemented dispatcher).

  When a command module **is loaded**, the CLI invokes its `run/2` callback with
  the parsed positional args and the parsed `OptionParser` switches map.

  The CLI never embeds any response payload. Output shaping (`--json` vs human)
  is performed on the value returned by the command module.
  """

  alias Chassis.CLI.Encoding

  @typedoc "Exit code returned by the underlying Mix-task or command module."
  @type exit_code :: non_neg_integer()

  @typedoc "Payload returned by the command module or the not-implemented router."
  @type payload :: map()

  @command_table %{
    "help" => {Chassis.CLI.Command.Help, phase: 0, package: :chassis_cli},
    "--help" => {Chassis.CLI.Command.Help, phase: 0, package: :chassis_cli},
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

  @doc false
  @spec command_table() :: %{optional(String.t()) => {module(), keyword()}}
  def command_table, do: @command_table

  @doc """
  Returns the list of all documented command keywords (used by `--help`).
  """
  @spec known_commands() :: [String.t()]
  def known_commands do
    @command_table
    |> Map.keys()
    |> Enum.reject(&(&1 in ["help", "--help"]))
    |> Enum.sort()
  end

  @spec main([String.t()]) :: no_return()
  def main(argv) do
    {code, payload} = dispatch(argv)
    IO.write(Encoding.encode(payload, json?: json?(argv)) <> "\n")
    System.halt(code)
  end

  @doc """
  Pure dispatch entry point: parses argv, resolves the command module, and
  either invokes `run/2` on the loaded module or returns a not-implemented
  error tuple with the structured phase/package metadata.

  Always returns `{exit_code, payload_map}`. Never embeds a static payload.
  """
  @spec dispatch([String.t()]) :: {exit_code(), payload()}
  def dispatch([]) do
    {0, %{command: "help", commands: known_commands()}}
  end

  def dispatch(argv) when is_list(argv) do
    {command_key, rest} = resolve_command_key(argv)
    {positional, switches} = parse_switches(rest)

    case Map.fetch(@command_table, command_key) do
      :error ->
        {1,
         %{
           error: "unknown_command",
           command: command_key,
           known_commands: known_commands()
         }}

      {:ok, {Chassis.CLI.Command.Help, _meta}} ->
        {0, %{command: "help", commands: known_commands()}}

      {:ok, {module, meta}} ->
        invoke(module, positional, switches, command_key, meta)
    end
  end

  defp resolve_command_key(argv) do
    case argv do
      [a, b | rest] ->
        joined = a <> "." <> b

        cond do
          Map.has_key?(@command_table, joined) -> {joined, rest}
          Map.has_key?(@command_table, a) -> {a, [b | rest]}
          true -> {a, [b | rest]}
        end

      [a | rest] ->
        {a, rest}

      [] ->
        {"help", []}
    end
  end

  defp parse_switches(argv) do
    {parsed, positional, _invalid} =
      OptionParser.parse(argv,
        strict: [
          dry_run: :boolean,
          env: :string,
          app: :string,
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
          no_mezzanine: :boolean,
          plaintext_vault: :boolean,
          profile: :string,
          receipts_dir: :string,
          require_citadel_consent: :boolean,
          require_health_gated_swap: :boolean,
          require_rollback_proof: :boolean,
          require_trial: :boolean,
          quota: :string,
          release_version: :string,
          residency: :string,
          runtime: :string,
          scenario: :string,
          suite: :string,
          tenant: :string,
          to: :string,
          vault_path: :string
        ],
        aliases: [p: :profile]
      )

    switches = Map.new(parsed)
    {positional, switches}
  rescue
    _ ->
      # Fallback: treat everything as positional if OptionParser cannot parse.
      {argv, %{}}
  end

  defp invoke(module, positional, switches, command_key, meta) do
    if Code.ensure_loaded?(module) and function_exported?(module, :run, 2) do
      try do
        case module.run(positional, switches) do
          {:ok, payload} when is_map(payload) ->
            {0, Map.put(payload, :command, command_key)}

          {:error, {:not_implemented, ^module, info}} ->
            not_implemented_payload(command_key, module, Keyword.merge(meta, info), routed?: true)

          {:error, {:not_implemented, ^module}} ->
            not_implemented_payload(command_key, module, meta, routed?: true)

          {:error, %{} = err} ->
            {1, Map.merge(%{error: "command_failed", command: command_key}, err)}

          {:error, reason} ->
            {1,
             %{
               error: "command_failed",
               command: command_key,
               reason: inspect(reason)
             }}

          other ->
            {1,
             %{
               error: "command_returned_invalid_shape",
               command: command_key,
               module: inspect(module),
               value: inspect(other)
             }}
        end
      rescue
        exception ->
          {1,
           %{
             error: "command_raised",
             command: command_key,
             module: inspect(module),
             exception: Exception.message(exception)
           }}
      end
    else
      not_implemented_payload(command_key, module, meta, routed?: false)
    end
  end

  defp not_implemented_payload(command_key, module, meta, opts) do
    phase = Keyword.get(meta, :phase, nil)
    package = Keyword.get(meta, :package, nil)

    {1,
     %{
       error: "not_implemented",
       command: command_key,
       module: inspect(module),
       routed?: Keyword.get(opts, :routed?, false),
       phase_gate: phase,
       package: package
     }}
  end

  defp json?(argv), do: Enum.member?(argv, "--json")
end

defmodule Chassis.CLI.Command do
  @moduledoc """
  Behaviour every `Chassis.CLI.Command.*` module must implement.

  The CLI router never embeds response payloads. It calls `run/2` on the
  resolved command module with the positional args and the parsed switches.

  Per `0541_implementation_readiness_corrections.md` §1 row 4, command modules
  that wrap an inactive package MUST return:

      {:error, {:not_implemented, __MODULE__}}

  or, when structured phase/package metadata is useful:

      {:error, {:not_implemented, __MODULE__, [phase: 11, package: :chassis_stack_manager]}}
  """
  @callback run([String.t()], map()) ::
              {:ok, map()}
              | {:error, term()}
              | {:error, {:not_implemented, module()}}
              | {:error, {:not_implemented, module(), keyword()}}
end

defmodule Chassis.CLI.Command.Help do
  @moduledoc "The only built-in command. Lists all known commands."
  @behaviour Chassis.CLI.Command

  @impl true
  def run(_positional, _switches) do
    {:ok, %{command: "help", commands: Chassis.CLI.known_commands()}}
  end
end

defmodule Chassis.CLI.Encoding do
  @moduledoc """
  Output encoders used by `Chassis.CLI`. The encoders are pure and never
  fabricate any data; they only render whatever the command module returned.
  """

  @spec encode(map(), keyword()) :: String.t()
  def encode(payload, opts) when is_map(payload) do
    if Keyword.get(opts, :json?, false), do: json(payload), else: human(payload)
  end

  defp human(%{command: "help", commands: commands}) do
    "commands:\n" <> Enum.join(Enum.map(commands, &("  " <> &1)), "\n")
  end

  defp human(%{error: error} = payload) do
    "ERROR " <> to_string(error) <> ": " <> inspect(Map.delete(payload, :error))
  end

  defp human(%{format: :table, columns: columns, rows: rows}) do
    Chassis.CLI.Table.render(columns, rows)
  end

  defp human(payload) do
    payload
    |> Enum.map_join("\n", fn {k, v} -> "#{k}: #{format_value(v)}" end)
  end

  defp format_value(v) when is_list(v), do: Enum.map_join(v, ", ", &format_value/1)
  defp format_value(v) when is_map(v), do: inspect(v)
  defp format_value(v), do: to_string(v)

  defp json(value) when is_map(value) do
    "{" <>
      (value
       |> Enum.map(fn {k, v} -> json_key(k) <> ":" <> json(v) end)
       |> Enum.join(",")) <>
      "}"
  end

  defp json(value) when is_list(value),
    do: "[" <> Enum.map_join(value, ",", &json/1) <> "]"

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
