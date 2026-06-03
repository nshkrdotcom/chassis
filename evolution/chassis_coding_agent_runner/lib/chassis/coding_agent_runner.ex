defmodule Chassis.Evolution.CodingAgentRunner.RunnerProfile do
  @moduledoc "External coding-agent runner profile."

  alias Chassis.Secrets.SecretRef

  @runner_kinds [:codex, :claude, :gemini, :amp, :opencode, :aider, :custom]
  @default_budget %{wall_ms: 30_000, max_cost_cents: 0, max_tokens: 0}

  @enforce_keys [:runner_kind, :binary_path_ref, :working_dir_ref]
  defstruct [
    :runner_kind,
    :binary_path_ref,
    :working_dir_ref,
    :prompt_template_ref,
    :redaction_profile_ref,
    args: [],
    env_overrides: [],
    budget_caps: @default_budget
  ]

  @type t :: %__MODULE__{}

  @spec runner_kinds() :: [atom()]
  def runner_kinds, do: @runner_kinds

  @spec new!(map() | keyword()) :: t()
  def new!(attrs) when is_map(attrs) or is_list(attrs) do
    attrs =
      attrs
      |> Map.new()
      |> Map.put_new(:runner_kind, :custom)
      |> Map.put_new(:budget_caps, @default_budget)
      |> Map.put_new(:env_overrides, [])
      |> Map.put_new(:args, [])
      |> Map.put_new(:redaction_profile_ref, "aitrace:export_bounds:default")

    validate_runner_kind!(attrs.runner_kind)
    validate_binary!(attrs, :binary_path_ref)
    validate_binary!(attrs, :working_dir_ref)
    validate_env_overrides!(attrs.env_overrides)
    struct!(__MODULE__, attrs)
  end

  @spec redaction_profile() :: map()
  def redaction_profile do
    profile =
      if Code.ensure_loaded?(AITrace.ExportBounds) and
           function_exported?(AITrace.ExportBounds, :profile, 0) do
        apply(AITrace.ExportBounds, :profile, [])
      else
        %{schema_version: "aitrace-export-bounds-fallback-v1"}
      end

    %{source: "AITrace.ExportBounds.profile/0", profile: profile}
  end

  defp validate_runner_kind!(kind) when kind in @runner_kinds, do: :ok

  defp validate_runner_kind!(kind),
    do: raise(ArgumentError, "unknown coding agent runner kind #{inspect(kind)}")

  defp validate_binary!(attrs, key) do
    case Map.get(attrs, key) do
      value when is_binary(value) and value != "" -> :ok
      _other -> raise ArgumentError, "#{key} must be a non-empty string"
    end
  end

  defp validate_env_overrides!(env_overrides) when is_list(env_overrides) do
    Enum.each(env_overrides, fn
      {name, %SecretRef{}} when is_binary(name) ->
        :ok

      {name, value} when is_binary(name) and is_binary(value) ->
        if sensitive_env_name?(name) do
          raise ArgumentError, "#{name} must be backed by Chassis.Secrets.SecretRef"
        end

      other ->
        raise ArgumentError, "invalid env override #{inspect(other)}"
    end)
  end

  defp sensitive_env_name?(name) do
    upper = String.upcase(name)

    String.contains?(upper, "TOKEN") or String.contains?(upper, "SECRET") or
      String.contains?(upper, "API_KEY")
  end
end

defmodule Chassis.Evolution.CodingAgentRunner.PortRunner do
  @moduledoc "Provider-agnostic external CLI runner."

  @behaviour Chassis.Evolution.CodingAgentRunner

  alias Chassis.Evolution.CodingAgentRunner.RunnerProfile
  alias Chassis.Evolution.DTO.{CodeAgentRun, FailureBatch}
  alias Chassis.Evolution.Receipts.CodingAgentRunRecord
  alias Chassis.Evolution.Receipts.Store.Memory, as: ReceiptMemory
  alias Chassis.Secrets.SecretRef

  @impl true
  def spawn_run(request, opts \\ []) do
    with {:ok, profile} <- profile(opts),
         {:ok, request} <- normalize_request(request),
         {:ok, result} <- run_profile(profile, request, opts) do
      {:ok, result}
    end
  end

  @impl true
  def cancel_run(_run_ref, _opts \\ []), do: {:error, :not_running}

  @spec fixture_request() :: map()
  def fixture_request do
    %{
      tenant_ref: "tenant:dev",
      installation_ref: "installation:dev",
      candidate_ref: "cand:dev:smoke",
      base_release_ref: "release:base:dev",
      failure_batch:
        FailureBatch.new!(%{
          failure_batch_ref: "failure_batch:phase25",
          tenant_ref: "tenant:dev",
          installation_ref: "installation:dev",
          evidence_refs: ["evidence:phase25"],
          summary: %{bytes: "bounded failure summary", max_bytes: 256},
          redaction_posture: :default,
          created_at: DateTime.utc_now()
        })
    }
  end

  defp profile(opts) do
    cond do
      Keyword.has_key?(opts, :runner_profile) ->
        {:ok, Keyword.fetch!(opts, :runner_profile)}

      Keyword.has_key?(opts, :binary_path_ref) ->
        {:ok,
         RunnerProfile.new!(%{
           runner_kind: Keyword.get(opts, :runner_kind, :custom),
           binary_path_ref: Keyword.fetch!(opts, :binary_path_ref),
           working_dir_ref: Keyword.get(opts, :working_dir_ref, System.tmp_dir!()),
           env_overrides: Keyword.get(opts, :env_overrides, []),
           budget_caps:
             Keyword.get(opts, :budget_caps, %{wall_ms: 30_000, max_cost_cents: 0, max_tokens: 0})
         })}

      true ->
        {:ok, fixture_profile(Keyword.get(opts, :runner_kind, :custom))}
    end
  end

  defp fixture_profile(runner_kind) do
    root = Path.join(System.tmp_dir!(), "chassis_port_runner_fixture")
    File.mkdir_p!(root)
    binary = Path.join(root, "fixture_echo_runner.sh")

    unless File.exists?(binary) do
      File.write!(binary, """
      #!/bin/sh
      printf 'diff --git a/lib/example.ex b/lib/example.ex\\n+ok\\n'
      printf 'cost_cents=0\\n'
      printf 'tokens=0\\n'
      """)

      File.chmod!(binary, 0o755)
    end

    RunnerProfile.new!(%{
      runner_kind: runner_kind,
      binary_path_ref: binary,
      working_dir_ref: root,
      budget_caps: %{wall_ms: 1_000, max_cost_cents: 0, max_tokens: 0}
    })
  end

  defp normalize_request(%{failure_batch: %FailureBatch{}} = request), do: {:ok, request}
  defp normalize_request(_request), do: {:error, :invalid_runner_request}

  defp run_profile(%RunnerProfile{} = profile, request, opts) do
    started_at = DateTime.utc_now()
    artifact_dir = artifact_dir(profile.working_dir_ref, request.candidate_ref)
    File.mkdir_p!(artifact_dir)

    prompt_summary = prompt_summary(request)
    prompt_summary_ref = artifact_ref(:prompt_summary, prompt_summary)
    prompt_summary_path = Path.join(artifact_dir, "prompt_summary")
    File.write!(prompt_summary_path, prompt_summary)

    wall_ms = get_in(profile.budget_caps, [:wall_ms]) || 30_000

    task =
      Task.async(fn ->
        execute_binary(profile, request, artifact_dir)
      end)

    case Task.yield(task, wall_ms) || Task.shutdown(task, :brutal_kill) do
      {:ok, {:ok, command_result}} ->
        build_success(
          command_result,
          profile,
          request,
          opts,
          started_at,
          prompt_summary_ref,
          artifact_dir
        )

      {:ok, {:error, reason}} ->
        {:error, reason}

      nil ->
        {:error, {:budget_exceeded, %{wall_ms: wall_ms, signal: :sigkill}}}
    end
  end

  defp execute_binary(profile, request, artifact_dir) do
    stderr_path = Path.join(artifact_dir, "stderr.raw")
    env = env(profile, request)

    shell = "binary=$1; stderr=$2; shift 2; exec \"$binary\" \"$@\" 2>\"$stderr\""

    {stdout, status} =
      System.cmd(
        "/bin/sh",
        ["-c", shell, "chassis-runner", profile.binary_path_ref, stderr_path | profile.args],
        cd: profile.working_dir_ref,
        env: env
      )

    stderr = if File.exists?(stderr_path), do: File.read!(stderr_path), else: ""
    {:ok, %{stdout: stdout, stderr: stderr, status: status}}
  rescue
    exception -> {:error, {:runner_spawn_failed, Exception.message(exception)}}
  end

  defp build_success(
         command_result,
         profile,
         request,
         opts,
         started_at,
         prompt_summary_ref,
         artifact_dir
       ) do
    completed_at = DateTime.utc_now()
    diff = extract_diff(command_result.stdout)
    diff_ref = artifact_ref(:diff, diff)
    log = redact(command_result.stderr, opts)
    log_ref = artifact_ref(:build_log, log)
    cost_ref = "cost:" <> digest(parse_line(command_result.stdout, "cost_cents=") || "0")
    token_ref = "token:" <> digest(parse_line(command_result.stdout, "tokens=") || "0")

    File.write!(Path.join(artifact_dir, "diff"), diff)
    File.write!(Path.join(artifact_dir, "build_log"), log)

    run =
      CodeAgentRun.new!(%{
        code_agent_run_ref:
          "code-agent-run:" <> digest({request.candidate_ref, started_at, diff_ref}),
        runner_kind: profile.runner_kind,
        candidate_ref: request.candidate_ref,
        failure_batch_ref: request.failure_batch.failure_batch_ref,
        started_at: started_at,
        completed_at: completed_at,
        exit_status: exit_status(command_result.status),
        prompt_summary_ref: prompt_summary_ref,
        diff_ref: diff_ref,
        cost_ref: cost_ref,
        token_ref: token_ref,
        log_ref: log_ref
      })

    with :ok <- maybe_write_receipt(run, request, opts) do
      {:ok, run}
    end
  end

  defp maybe_write_receipt(%CodeAgentRun{} = run, request, opts) do
    record =
      CodingAgentRunRecord.new!(%{
        tenant_ref: request.tenant_ref,
        installation_ref: request.installation_ref,
        trace_id: Map.get(request, :trace_id, "trace:" <> digest(run.code_agent_run_ref)),
        code_agent_run_ref: run.code_agent_run_ref,
        runner_kind: run.runner_kind,
        candidate_ref: run.candidate_ref,
        failure_batch_ref: run.failure_batch_ref,
        started_at: run.started_at,
        completed_at: run.completed_at,
        exit_status: run.exit_status,
        prompt_summary_ref: run.prompt_summary_ref,
        diff_ref: run.diff_ref,
        cost_ref: run.cost_ref,
        token_ref: run.token_ref,
        log_ref: run.log_ref,
        summary: %{bytes: "coding agent run #{run.code_agent_run_ref}", max_bytes: 256},
        inserted_at: run.completed_at
      })

    case Keyword.fetch(opts, :receipts_store) do
      {:ok, store} ->
        case ReceiptMemory.put(store, record) do
          {:ok, _record} -> :ok
          {:error, reason} -> {:error, {:receipt_write_failed, reason}}
        end

      :error ->
        :ok
    end
  end

  defp env(profile, request) do
    base = [
      {"CHASSIS_CANDIDATE_REF", request.candidate_ref},
      {"CHASSIS_FAILURE_BATCH_REF", request.failure_batch.failure_batch_ref}
    ]

    profile_env =
      Enum.map(profile.env_overrides, fn
        {name, %SecretRef{} = ref} -> {name, "secret-ref:#{ref.secret_ref}"}
        {name, value} -> {name, value}
      end)

    base ++ profile_env
  end

  defp prompt_summary(request) do
    "candidate=#{request.candidate_ref}\nfailure_batch=#{request.failure_batch.failure_batch_ref}\nsummary=#{request.failure_batch.summary.bytes}\n"
  end

  defp artifact_dir(root, candidate_ref) do
    Path.join(root, safe_ref(candidate_ref))
  end

  defp safe_ref(ref), do: Regex.replace(~r/[^A-Za-z0-9_.-]/, ref, "_")

  defp artifact_ref(kind, bytes), do: "stage:#{kind}:#{digest(bytes)}"

  defp digest(value) do
    :crypto.hash(:sha256, :erlang.term_to_binary(value))
    |> Base.encode16(case: :lower)
    |> binary_part(0, 24)
  end

  defp extract_diff(stdout) do
    stdout
    |> String.split("\n", trim: false)
    |> Enum.reject(
      &(String.starts_with?(&1, "cost_cents=") or String.starts_with?(&1, "tokens="))
    )
    |> Enum.join("\n")
  end

  defp parse_line(stdout, prefix) do
    stdout
    |> String.split("\n")
    |> Enum.find_value(fn line ->
      if String.starts_with?(line, prefix), do: String.replace_prefix(line, prefix, ""), else: nil
    end)
  end

  defp redact(log, opts) do
    Enum.reduce(Keyword.get(opts, :redact_values, []), log, fn
      value, acc when is_binary(value) and value != "" -> String.replace(acc, value, "[REDACTED]")
      _value, acc -> acc
    end)
  end

  defp exit_status(0), do: :ok
  defp exit_status(_status), do: :error
end

for {runner, runner_kind} <- [
      {Codex, :codex},
      {Claude, :claude},
      {Gemini, :gemini},
      {Amp, :amp},
      {OpenCode, :opencode},
      {Aider, :aider},
      {Custom, :custom}
    ] do
  defmodule Module.concat(Chassis.Evolution.CodingAgentRunner.Runner, runner) do
    @moduledoc "Runner adapter."
    @behaviour Chassis.Evolution.CodingAgentRunner
    @runner_kind runner_kind

    @impl true
    def spawn_run(request, opts \\ []) do
      profile =
        opts
        |> Keyword.fetch!(:runner_profile)
        |> Map.put(:runner_kind, @runner_kind)

      Chassis.Evolution.CodingAgentRunner.PortRunner.spawn_run(
        request,
        Keyword.put(opts, :runner_profile, profile)
      )
    end

    @impl true
    def cancel_run(run_ref, opts \\ []) do
      Chassis.Evolution.CodingAgentRunner.PortRunner.cancel_run(run_ref, opts)
    end
  end
end
